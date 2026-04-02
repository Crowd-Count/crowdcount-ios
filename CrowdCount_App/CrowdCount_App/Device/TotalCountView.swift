import SwiftUI
import UserNotifications

struct LocationTotalCountView: View {
    let currentCount: Int
    let isClosed: Bool
    let overcrowdingLimit: Int?
    let locationName: String
    let locationId: String
    let devices: [Device]
    let deviceStatuses: [String: String]
    @ObservedObject var alertViewModel: AlertViewModel
    let incompleteLocationWarnings: [IncompleteLocationWarning]
    let onDismissIncompleteWarning: (String, Int) -> Void  // (warningId, deviceCount)
    let addToCount: (Int) -> Void
    let subFromCount: (Int) -> Void
    @Binding var location: AppLocation
    let onLocationUpdated: (AppLocation) -> Void
    var onEditClosingTime: (() -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme

    // Overcrowding state
    @State private var showOvercrowdingSheet: Bool = false
    @State private var newOvercrowdingLimit: String = ""
    @State private var isOvercrowdingEnabled: Bool = false
    @State private var isOvercrowdingNotificationEnabled: Bool = false
    @State private var isLoadingOvercrowding: Bool = false

    // Counters that are offline
    private var offlineCounters: [Device] {
        devices.filter { deviceStatuses[$0.deviceId] != "online" }
    }

    private var signingDevice: (String, String)? {
        guard let first = devices.first else { return nil }
        return (first.deviceId, first.password)
    }

    /// Warnings relevant to this location's devices
    private var relevantWarnings: [IncompleteLocationWarning] {
        let localIds = Set(devices.map { $0.deviceId })
        return incompleteLocationWarnings.filter { warning in
            !Set(warning.userDeviceIds).isDisjoint(with: localIds)
        }
    }

    var body: some View {
        VStack {
            Spacer().frame(maxHeight: 60)

                // WiFi status icons for all counters
                if !devices.isEmpty {
                    VStack(spacing: 4) {
                        // Reserve fixed space at top — offline message fills it, otherwise empty
                        if !offlineCounters.isEmpty {
                            Text("\(offlineCounters.count) counter\(offlineCounters.count == 1 ? "" : "s") offline")
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(height: 20)
                        } else {
                            Spacer().frame(height: 20)
                        }

                        HStack(alignment: .center, spacing: 8) {
                            ForEach(devices) { device in
                                let isOffline = deviceStatuses[device.deviceId] != "online"
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
                    }
                    .padding(.bottom, 6)
                } else {
                    Spacer().frame(height: 20)
                }

                VStack(spacing: 4) {
                    Text(isClosed ? "Status for" : (offlineCounters.isEmpty ? "Live Count for" : "Total Count for"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text(locationName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Count display
                Group {
                    if isClosed {
                        VStack(spacing: 8) {
                            Text("Closed")
                                .font(.system(size: 50))
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            if let onEditClosingTime = onEditClosingTime {
                                Button(action: onEditClosingTime) {
                                    Text("Edit Closing Times")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    } else if let limit = overcrowdingLimit, limit > 0 {
                        HStack(alignment: .center, spacing: 0) {
                            Text("\(currentCount)")
                                .fontWeight(.bold)
                            Text(" / ")
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .baselineOffset(2)
                            Text("\(limit)")
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 75))
                    } else {
                        Text("\(currentCount)")
                            .fontWeight(.bold)
                            .font(.system(size: 75))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // +/- buttons
                HStack(spacing: 0) {
                    Button(action: { subFromCount(1) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(currentCount <= 0 || isClosed ? .secondary : .primary)
                            .frame(width: 44, height: 36)
                    }
                    .disabled(currentCount <= 0 || isClosed)

                    Divider()
                        .frame(height: 20)

                    Button(action: { addToCount(1) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isClosed ? .secondary : .primary)
                            .frame(width: 44, height: 36)
                    }
                    .disabled(isClosed)
                }
                .background(Color.secondary.opacity(0.25))
                .clipShape(Capsule())
                .opacity(isClosed ? 0.5 : 1.0)
                .padding(.bottom, 8)

                // Incomplete on-map location warning banner
                ForEach(relevantWarnings) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            let deviceId = warning.userDeviceIds.first ?? ""
                            let missing = warning.totalDeviceCount - warning.userDeviceIds.count
                            (Text("\(deviceId)").bold()
                             + Text(" is part of ")
                             + Text("\(warning.serverLocationName)").bold()
                             + Text(" on the map with \(warning.totalDeviceCount) counters. Add the remaining \(missing) counter\(missing == 1 ? "" : "s") for complete data."))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Button(action: {
                            onDismissIncompleteWarning(warning.id, warning.totalDeviceCount)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.15))
                    )
                    .padding(.horizontal, 20)
                }

                // --- Action buttons ---
                VStack(spacing: 10) {
                    NavigationLink(destination: LocationHistoricView(location: location, devices: devices, initialTab: .historicCounts)) {
                        actionButton(icon: "chart.bar.xaxis", text: "History", bg: .blue)
                    }

                    NavigationLink(destination: LocationHistoricView(location: location, devices: devices, initialTab: .insights)) {
                        actionButton(icon: "lightbulb.fill", text: "Insights", bg: .blue)
                    }

                    Button {
                        if let limit = location.overcrowdingLimit, limit > 0 {
                            newOvercrowdingLimit = String(limit)
                        } else {
                            newOvercrowdingLimit = ""
                        }
                        showOvercrowdingSheet = true
                    } label: {
                        actionButton(
                            icon: isOvercrowdingEnabled && isOvercrowdingNotificationEnabled ? "bell.fill" : "bell.slash",
                            text: "Overcrowding",
                            bg: .gray
                        )
                    }
                    .sheet(isPresented: $showOvercrowdingSheet) {
                        OvercrowdingSettingsSheet(
                            isPresented: $showOvercrowdingSheet,
                            limitText: $newOvercrowdingLimit,
                            isEnabled: $isOvercrowdingEnabled,
                            notificationsEnabled: $isOvercrowdingNotificationEnabled,
                            isLoading: $isLoadingOvercrowding,
                            currentLimit: location.overcrowdingLimit,
                            onSave: { limit in
                                saveOvercrowdingLimit(limit: limit)
                            },
                            onDelete: {
                                saveOvercrowdingLimit(limit: 0)
                            },
                            onToggleNotifications: { enabled in
                                if enabled {
                                    registerForLocationNotifications()
                                } else {
                                    unregisterFromLocationNotifications()
                                }
                            }
                        )
                        .presentationDetents([.medium])
                    }

                    if location.isOnMap {
                        if !offlineCounters.isEmpty {
                            actionButton(icon: "megaphone.fill", text: "Create a Promo", bg: .gray)
                                .opacity(0.4)
                        } else {
                            NavigationLink(destination: AdPayView(
                                locationId: locationId,
                                locationName: locationName,
                                credentials: devices.map { ["device_id": $0.deviceId, "password": $0.password] }
                            )) {
                                actionButton(icon: "megaphone.fill", text: "Create a Promo", bg: .orange)
                            }
                        }
                    } else {
                        NavigationLink(destination: GetOnMapInfoView()) {
                            actionButton(icon: "map.fill", text: "Get on the Map", bg: .green)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .padding(.bottom, 16)
            .onAppear {
            checkOvercrowdingStatus()
        }
    }

    // MARK: - Overcrowding Methods

    private func checkOvercrowdingStatus() {
        if let limit = location.overcrowdingLimit, limit > 0 {
            isOvercrowdingEnabled = true
            isOvercrowdingNotificationEnabled = location.isOvercrowdingNotificationEnabled

            // Verify notification status with server
            if let appId = UserDefaults.standard.string(forKey: "appId") {
                Task {
                    let enabled = try? await APIService.shared.checkLocationOvercrowdingNotification(
                        locationId: locationId,
                        appId: appId
                    )
                    await MainActor.run {
                        isOvercrowdingNotificationEnabled = enabled ?? false
                    }
                }
            }
        } else {
            isOvercrowdingEnabled = false
            isOvercrowdingNotificationEnabled = false
        }
    }

    private func actionButton(icon: String, text: String, bg: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
            Text(text)
                .font(.body)
//                .fontWeight(.semibold)
        }
        .foregroundColor(.primary)
        .frame(width: 220)
        .padding(.vertical, 14)
        .background(bg.opacity(0.75))
        .cornerRadius(20)
    }

    private func saveOvercrowdingLimit(limit: Int) {
        isLoadingOvercrowding = true

        let creds = devices.map { ["device_id": $0.deviceId, "password": $0.password] }
        guard !creds.isEmpty,
              let firstDevice = devices.first else {
            isLoadingOvercrowding = false
            return
        }

        let signingDevice = (firstDevice.deviceId, firstDevice.password)

        Task {
            do {
                // 1. Update on server
                try await APIService.shared.updateLocation(
                    locationId: locationId,
                    overcrowdingLimit: limit,
                    credentials: creds,
                    signingDevice: signingDevice
                )

                // 2. Immediately pull back from server to confirm
                let serverLocation = try await APIService.shared.getLocation(
                    locationId: locationId,
                    credentials: creds,
                    signingDevice: signingDevice
                )

                await MainActor.run {
                    var updatedLocation = location
                    updatedLocation.overcrowdingLimit = serverLocation.overcrowdingLimit
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)

                    isOvercrowdingEnabled = (serverLocation.overcrowdingLimit ?? 0) > 0
                    if (serverLocation.overcrowdingLimit ?? 0) == 0 {
                        isOvercrowdingNotificationEnabled = false
                    }
                    isLoadingOvercrowding = false
                }
            } catch {
                print("Error updating overcrowding limit: \(error)")
                // Still update locally as fallback
                await MainActor.run {
                    let newLimit: Int? = limit > 0 ? limit : nil
                    var updatedLocation = location
                    updatedLocation.overcrowdingLimit = newLimit
                    location = updatedLocation
                    onLocationUpdated(updatedLocation)

                    isOvercrowdingEnabled = limit > 0
                    if limit == 0 {
                        isOvercrowdingNotificationEnabled = false
                    }
                    isLoadingOvercrowding = false
                }
            }
        }
    }

    private func registerForLocationNotifications() {
        guard let appId = UserDefaults.standard.string(forKey: "appId"),
              let signing = signingDevice else { return }

        // Optimistically update
        var updatedLocation = location
        updatedLocation.isOvercrowdingNotificationEnabled = true
        location = updatedLocation
        onLocationUpdated(updatedLocation)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            Task {
                do {
                    try await APIService.shared.registerLocationOvercrowdingNotification(
                        locationId: locationId,
                        appId: appId,
                        signingDevice: signing
                    )
                } catch {
                    print("Error registering for location notifications: \(error)")
                }
            }
        }
    }

    private func unregisterFromLocationNotifications() {
        guard let appId = UserDefaults.standard.string(forKey: "appId"),
              let signing = signingDevice else { return }

        // Optimistically update
        var updatedLocation = location
        updatedLocation.isOvercrowdingNotificationEnabled = false
        location = updatedLocation
        onLocationUpdated(updatedLocation)

        Task {
            do {
                try await APIService.shared.unregisterLocationOvercrowdingNotification(
                    locationId: locationId,
                    appId: appId,
                    signingDevice: signing
                )
            } catch {
                print("Error unregistering from location notifications: \(error)")
            }
        }
    }
}

// MARK: - Overcrowding Settings Sheet (reused from old TotalCountView)

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
                        let newLimit = Int(limitText) ?? 0
                        if newLimit == 0 && isEnabled {
                            onSave(0)
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
