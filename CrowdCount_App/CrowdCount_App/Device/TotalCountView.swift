import SwiftUI

struct TotalCountView: View {
    let totalCount: Int
    let totalOvercrowdingCount: Int
    let users: [User]
    @Binding var userPasswords: [UUID: String]
    let locationName: String
    @ObservedObject var alertViewModel: AlertViewModel
    let serverURL: String
    let onLocationMapStatusChanged: (Bool) -> Void  // Callback when map status changes
    let onMapDataFetched: ([String: String], [String: String]) -> Void  // Callback with (deviceLocationNames, devicePrimaryDevices)
    let isBluetoothSetupRequired: [UUID: Bool]  // Offline status for each device
    let isCountLoaded: [UUID: Bool]  // Track if initial count has been fetched
    @Binding var location: CounterLocation  // Location binding for overcrowding updates
    let onLocationUpdated: (CounterLocation) -> Void  // Callback when location is updated

    @Environment(\.colorScheme) var colorScheme

    // Map status state
    @State private var isLocationOnMap: Bool = false
    @State private var deviceLocationNames: [String: String] = [:]
    @State private var devicePrimaryDevices: [String: String] = [:]

    // Overcrowding state
    @State private var showOvercrowdingSheet: Bool = false
    @State private var newOvercrowdingLimit: String = ""
    @State private var isOvercrowdingEnabled: Bool = false
    @State private var isOvercrowdingNotificationEnabled: Bool = false
    @State private var isLoadingOvercrowding: Bool = false

    // Check if this location has a demo device
    private var hasDemoDevice: Bool {
        users.contains { $0.userId == "Demo" }
    }

    // Devices in this location that are NOT on the map
    private var extraDevices: [User] {
        guard isLocationOnMap else { return [] }
        return users.filter { !deviceLocationNames.keys.contains($0.userId) && $0.userId != "Demo" }
    }

    // Device IDs that belong to this map location but are NOT in the app
    private var missingMapDevices: [String] {
        guard isLocationOnMap else { return [] }
        let userDeviceIds = Set(users.map { $0.userId })
        // Find all devices that belong to this location name on the map
        let mapDevicesForThisLocation = deviceLocationNames.filter { $0.value == locationName }.map { $0.key }
        // Return ones not in the app
        return mapDevicesForThisLocation.filter { !userDeviceIds.contains($0) }
    }

    // Counters that are offline (need Bluetooth setup / not connected to WiFi)
    private var offlineCounters: [User] {
        users.filter { isBluetoothSetupRequired[$0.id] == true }
    }

    // Check if all counts have been loaded
    private var allCountsLoaded: Bool {
        users.allSatisfy { isCountLoaded[$0.id] == true }
    }

    var body: some View {
        VStack {
            Spacer()
            Spacer().frame(height: 15)

            // WiFi status icons for all counters
            if !users.isEmpty {
                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(users) { user in
                            let isOffline = isBluetoothSetupRequired[user.id] == true
                            Image(systemName: isOffline ? "wifi.slash" : "wifi")
                                .foregroundColor(isOffline ? .red : .green)
                                .font(.system(size: 18))
                                .symbolRenderingMode(.hierarchical)
                                .offset(y: isOffline ? -1 : 0)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Group {
                            if #available(iOS 26.0, *) {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .glassEffect(.regular)
                            } else {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }

                    if !offlineCounters.isEmpty {
                        Text("\(offlineCounters.count) counter\(offlineCounters.count == 1 ? "" : "s") offline")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.bottom, 6)
            }

            VStack(spacing: 4) {
                Text(offlineCounters.isEmpty ? "Live Count for" : "Total Count for")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(locationName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Group {
                if !allCountsLoaded {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(height: 75)
                } else if totalOvercrowdingCount > 0 {
                    HStack(alignment: .center, spacing: 0) {
                        Text("\(totalCount)")
                            .fontWeight(.bold)
                        Text(" / ")
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .baselineOffset(2)
                        Text("\(totalOvercrowdingCount)")
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("\(totalCount)")
                        .fontWeight(.bold)
                }
            }
            .font(.system(size: 75))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            NavigationLink(destination: AggregatedHistoricView(users: users, userPasswords: $userPasswords)) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Count Analytics")
                }
                .padding()
                .background(Color.blue.opacity(0.75))
                .foregroundColor(.primary)
                .cornerRadius(20)
                .padding(.horizontal, 16)
            }

            // Overcrowding button
            Button(action: {
                // Initialize the text field with current limit
                if let limit = location.overcrowdingLimit, limit > 0 {
                    newOvercrowdingLimit = String(limit)
                } else {
                    newOvercrowdingLimit = ""
                }
                showOvercrowdingSheet = true
            }) {
                HStack(spacing: 8) {
                    if isOvercrowdingEnabled && isOvercrowdingNotificationEnabled {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "bell.slash")
                            .foregroundColor(.primary)
                    }
                    Text("Overcrowding")
                        .foregroundColor(.primary)
                }
                .padding()
                .background(Color.secondary.opacity(0.5))
                .cornerRadius(20)
            }
            .padding(.top, 10)
            .sheet(isPresented: $showOvercrowdingSheet) {
                OvercrowdingSettingsSheet(
                    isPresented: $showOvercrowdingSheet,
                    limitText: $newOvercrowdingLimit,
                    isEnabled: $isOvercrowdingEnabled,
                    notificationsEnabled: $isOvercrowdingNotificationEnabled,
                    isLoading: $isLoadingOvercrowding,
                    currentLimit: location.overcrowdingLimit,
                    onSave: { limit in
                        if limit == 0 {
                            deleteOvercrowdingGroup()
                        } else if let existingGroupId = location.overcrowdingGroupId {
                            updateOvercrowdingGroup(groupId: existingGroupId, limit: limit)
                        } else {
                            createOvercrowdingGroup(limit: limit)
                        }
                    },
                    onDelete: {
                        deleteOvercrowdingGroup()
                    },
                    onToggleNotifications: { enabled in
                        if enabled {
                            registerForGroupNotifications()
                        } else {
                            unregisterFromGroupNotifications()
                        }
                    }
                )
                .presentationDetents([.medium])
            }

            // Ad/Map buttons
            if isLocationOnMap || hasDemoDevice {
                let hasOfflineCounters = !offlineCounters.isEmpty
                let preselectedDevice = location.mapPrimaryDevice ?? users.first(where: { deviceLocationNames.keys.contains($0.userId) })?.userId

                if hasOfflineCounters {
                    // Greyed out button when counters are offline
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "megaphone.fill")
                            Text("Create a Promo")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.4))
                        .foregroundColor(.secondary)
                        .cornerRadius(20)
                        .padding(.horizontal, 16)
                    }
                    .disabled(true)
                    .padding(.top, 10)

                    Text("All counters must be online to create a promo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    NavigationLink(destination: AdPayView(users: .constant(users), deviceLocationNames: deviceLocationNames, devicePrimaryDevices: devicePrimaryDevices, preselectedDeviceId: preselectedDevice)) {
                        HStack {
                            Image(systemName: "megaphone.fill")
                            Text("Create a Promo")
                        }
                        .padding()
                        .background(Color.orange.opacity(0.75))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 10)
                }
            } else {
                NavigationLink(destination: GetOnMapInfoView()) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Get on the Map")
                    }
                    .padding()
                    .background(Color.green.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }

            Spacer().frame(height: 30)

            // Warning about extra devices not on map
            if !extraDevices.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(extraDevices.count) counter\(extraDevices.count == 1 ? " is" : "s are") not on the public map.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }

            // Warning about missing map devices
            if !missingMapDevices.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Add \(missingMapDevices.count) more counter\(missingMapDevices.count == 1 ? "" : "s") to complete this location: \(missingMapDevices.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
            }

//            Text("Counts and history are aggregated from all of your counters in \(locationName).")
//                .font(.footnote)
//                .foregroundColor(.secondary)
//                .multilineTextAlignment(.center)
//                .padding(.horizontal)
            Spacer()
        }
        .padding()
        .onAppear {
            checkIfLocationIsOnMap()
            checkOvercrowdingStatus()
        }
    }

    // MARK: - Overcrowding Methods

    private func checkOvercrowdingStatus() {
        // Check if location already has an overcrowding group
        if let groupId = location.overcrowdingGroupId {
            isOvercrowdingEnabled = true
            isOvercrowdingNotificationEnabled = location.isOvercrowdingNotificationEnabled

            // Fetch current status from server
            Task {
                if let appId = UserDefaults.standard.string(forKey: "appId") {
                    let enabled = try? await APIService.shared.checkGroupNotificationStatus(groupId: groupId, appId: appId)
                    await MainActor.run {
                        isOvercrowdingNotificationEnabled = enabled ?? false
                    }
                }
            }
        } else if let limit = location.overcrowdingLimit, limit > 0 {
            // Has local limit but no group yet
            isOvercrowdingEnabled = true
        } else {
            isOvercrowdingEnabled = false
            isOvercrowdingNotificationEnabled = false
        }
    }

    private func createOvercrowdingGroup(limit: Int) {
        let deviceIds = users.map { $0.userId }
        guard !deviceIds.isEmpty else { return }

        isLoadingOvercrowding = true

        Task {
            do {
                let groupId = try await APIService.shared.createOvercrowdingGroup(
                    deviceIds: deviceIds,
                    limit: limit,
                    groupName: locationName
                )

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.overcrowdingGroupId = groupId
                    updatedLocation.overcrowdingLimit = limit
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)

                    isOvercrowdingEnabled = true
                    isLoadingOvercrowding = false
                }
            } catch {
                print("Error creating overcrowding group: \(error)")
                await MainActor.run {
                    isLoadingOvercrowding = false
                }
            }
        }
    }

    private func updateOvercrowdingGroup(groupId: String, limit: Int) {
        let deviceIds = users.map { $0.userId }

        isLoadingOvercrowding = true

        Task {
            do {
                try await APIService.shared.updateOvercrowdingGroup(
                    groupId: groupId,
                    deviceIds: deviceIds,
                    limit: limit
                )

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.overcrowdingLimit = limit
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)

                    isLoadingOvercrowding = false
                }
            } catch {
                print("Error updating overcrowding group: \(error)")
                await MainActor.run {
                    isLoadingOvercrowding = false
                }
            }
        }
    }

    private func deleteOvercrowdingGroup() {
        guard let groupId = location.overcrowdingGroupId else {
            // Just clear local state
            var updatedLocation = location
            updatedLocation.overcrowdingLimit = nil
            location = updatedLocation
            onLocationUpdated(updatedLocation)
            isOvercrowdingEnabled = false
            isOvercrowdingNotificationEnabled = false
            return
        }

        isLoadingOvercrowding = true

        Task {
            do {
                // Unregister from notifications first if enabled
                if location.isOvercrowdingNotificationEnabled,
                   let appId = UserDefaults.standard.string(forKey: "appId") {
                    try? await APIService.shared.unregisterGroupNotification(groupId: groupId, appId: appId)
                }

                // Then delete the group
                try await APIService.shared.deleteOvercrowdingGroup(groupId: groupId)

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.overcrowdingGroupId = nil
                    updatedLocation.overcrowdingLimit = nil
                    updatedLocation.isOvercrowdingNotificationEnabled = false
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)

                    isOvercrowdingEnabled = false
                    isOvercrowdingNotificationEnabled = false
                    isLoadingOvercrowding = false
                }
            } catch {
                print("Error deleting overcrowding group: \(error)")
                await MainActor.run {
                    isLoadingOvercrowding = false
                }
            }
        }
    }

    private func registerForGroupNotifications() {
        guard let groupId = location.overcrowdingGroupId,
              let appId = UserDefaults.standard.string(forKey: "appId") else { return }

        Task {
            do {
                try await APIService.shared.registerGroupNotification(groupId: groupId, appId: appId)

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.isOvercrowdingNotificationEnabled = true
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)
                }
            } catch {
                print("Error registering for notifications: \(error)")
                await MainActor.run {
                    isOvercrowdingNotificationEnabled = false
                }
            }
        }
    }

    private func unregisterFromGroupNotifications() {
        guard let groupId = location.overcrowdingGroupId,
              let appId = UserDefaults.standard.string(forKey: "appId") else { return }

        Task {
            do {
                try await APIService.shared.unregisterGroupNotification(groupId: groupId, appId: appId)

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.isOvercrowdingNotificationEnabled = false
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)
                }
            } catch {
                print("Error unregistering from notifications: \(error)")
                await MainActor.run {
                    isOvercrowdingNotificationEnabled = true
                }
            }
        }
    }

    /// Check if any device in this location is on the public map
    func checkIfLocationIsOnMap() {
        guard let url = URL(string: "\(serverURL)/get_all_location_data_with_extra") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error checking map locations: \(String(describing: error))")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let locations = json["locations"] as? [[String: Any]] {

                var locationNames: [String: String] = [:]
                var primaryDevices: [String: String] = [:]

                for location in locations {
                    guard let primaryDeviceId = location["location_device"] as? String,
                          let mapLocationName = location["location_name"] as? String else {
                        continue
                    }

                    locationNames[primaryDeviceId] = mapLocationName
                    primaryDevices[primaryDeviceId] = primaryDeviceId

                    if let deviceBreakdown = location["device_breakdown"] as? [[String: Any]] {
                        for device in deviceBreakdown {
                            if let deviceId = device["device_id"] as? String {
                                locationNames[deviceId] = mapLocationName
                                primaryDevices[deviceId] = primaryDeviceId
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.deviceLocationNames = locationNames
                    self.devicePrimaryDevices = primaryDevices

                    // Check if ANY device in this location is on the map
                    let onMap = self.users.contains { locationNames.keys.contains($0.userId) }
                    self.isLocationOnMap = onMap

                    // Notify parent about map status change
                    self.onLocationMapStatusChanged(onMap)

                    // Pass map data to parent for device ownership checks
                    self.onMapDataFetched(locationNames, primaryDevices)
                }
            }
        }.resume()
    }
}

// MARK: - Overcrowding Settings Sheet

struct OvercrowdingSettingsSheet: View {
    @Binding var isPresented: Bool
    @Binding var limitText: String
    @Binding var isEnabled: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var isLoading: Bool
    let currentLimit: Int?
    let onSave: (Int) -> Void
    let onDelete: () -> Void
    let onToggleNotifications: (Bool) -> Void

    @State private var hasUnsavedChanges: Bool = false

    private var hasValidLimit: Bool {
        if let limit = Int(limitText), limit > 0 {
            return true
        }
        return false
    }

    private var limitChanged: Bool {
        let newLimit = Int(limitText) ?? 0
        let oldLimit = currentLimit ?? 0
        return newLimit != oldLimit && hasValidLimit
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Overcrowding Limit"), footer: Text("Get alerted when the total count exceeds this limit.")) {
                    HStack {
                        TextField("Enter limit", text: $limitText)
                            .keyboardType(.numberPad)
                            .onChange(of: limitText) { _, _ in
                                hasUnsavedChanges = limitChanged
                            }
                        if !limitText.isEmpty {
                            Button(action: { limitText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if hasUnsavedChanges {
                        Button(action: {
                            if let limit = Int(limitText), limit > 0 {
                                onSave(limit)
                                hasUnsavedChanges = false
                            }
                        }) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Set Limit")
                                        .fontWeight(.medium)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoading)
                    }
                }

                Section(header: Text("Notifications")) {
                    Toggle(isOn: Binding(
                        get: { notificationsEnabled },
                        set: { newValue in
                            notificationsEnabled = newValue
                            onToggleNotifications(newValue)
                        }
                    )) {
                        HStack {
                            Image(systemName: notificationsEnabled && isEnabled ? "bell.fill" : "bell.slash")
                                .foregroundColor(notificationsEnabled && isEnabled ? .primary : .secondary)
                            Text("Push Notifications")
                                .foregroundColor(isEnabled ? .primary : .secondary)
                        }
                    }
                    .disabled(!isEnabled)
                }

                if isEnabled {
                    Section {
                        Button(role: .destructive, action: {
                            onDelete()
                            isPresented = false
                        }) {
                            HStack {
                                Spacer()
                                Text("Remove Overcrowding Limit")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Overcrowding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // If text is empty or zero and there was a limit, remove it
                        let newLimit = Int(limitText) ?? 0
                        if newLimit == 0 && isEnabled {
                            onSave(0)  // This triggers deletion
                        } else if hasUnsavedChanges && newLimit > 0 {
                            onSave(newLimit)
                        }
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct TotalCountView_Previews: PreviewProvider {
    static var previews: some View {
        TotalCountView(
            totalCount: 125,
            totalOvercrowdingCount: 200,
            users: [],
            userPasswords: .constant([:]),
            locationName: "Grand Central",
            alertViewModel: AlertViewModel(),
            serverURL: "https://api.example.com",
            onLocationMapStatusChanged: { _ in },
            onMapDataFetched: { _, _ in },
            isBluetoothSetupRequired: [:],
            isCountLoaded: [:],
            location: .constant(CounterLocation(
                id: UUID(),
                name: "Grand Central",
                deviceIds: [],
                overcrowdingLimit: 200,
                isMapLocation: false,
                mapPrimaryDevice: nil
            )),
            onLocationUpdated: { _ in }
        )
    }
}
