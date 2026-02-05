import SwiftUI

struct LocationSettingsView: View {
    @Binding var location: CounterLocation
    let users: [User]  // All users (to show which are in this location)
    let onSave: () -> Void
    let onDelete: () -> Void
    let mapDeviceIds: Set<String>  // Device IDs that are on the public map
    let isBluetoothSetupRequired: [UUID: Bool]  // Offline status for each device
    let userPasswords: [UUID: String]  // Passwords for each user
    let serverURL: String
    var onCountsReset: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appSettings: AppSettings
    @State private var locationName: String = ""
    @State private var selectedColor: String = "orange"
    @State private var showDeleteConfirmation: Bool = false

    // Daily Reset state
    @State private var hasResetSchedule: Bool = false
    @State private var selectedResetTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
    @State private var selectedTimezone: String = TimeZone.current.identifier
    @State private var isLoadingSchedule: Bool = true
    @State private var isSavingSchedule: Bool = false
    private let apiService = APIService.shared

    // Reset All Counters state
    @State private var showResetAllConfirmation: Bool = false
    @State private var isResettingAll: Bool = false
    @State private var resetAllResult: String? = nil
    @State private var showResetAllResult: Bool = false

    // Common timezones for picker
    private let commonTimezones: [(id: String, label: String)] = [
        ("America/New_York", "Eastern (ET)"),
        ("America/Chicago", "Central (CT)"),
        ("America/Denver", "Mountain (MT)"),
        ("America/Los_Angeles", "Pacific (PT)"),
        ("America/Phoenix", "Arizona (MST)"),
        ("America/Anchorage", "Alaska (AKT)"),
        ("Pacific/Honolulu", "Hawaii (HST)"),
        ("Europe/London", "London (GMT/BST)"),
        ("Europe/Paris", "Paris (CET)"),
        ("Europe/Berlin", "Berlin (CET)"),
        ("Asia/Tokyo", "Tokyo (JST)"),
        ("Asia/Shanghai", "Shanghai (CST)"),
        ("Asia/Dubai", "Dubai (GST)"),
        ("Australia/Sydney", "Sydney (AEST)"),
        ("UTC", "UTC"),
    ]

    var body: some View {
        NavigationView {
            Form {
                // Location Name
                Section(header: Text("Location Name"), footer: location.isMapLocation ? Text("Name is synced from the public map. Email info@crowdcount.tech to request changes.") : nil) {
                    if location.isMapLocation {
                        Text(locationName)
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Location name", text: $locationName)
                            .onChange(of: locationName) { _, newValue in
                                location.name = newValue
                            }
                    }
                }

                // Counters in this location
                Section(header: Text("Counters (\(location.deviceIds.count))")) {
                    if location.deviceIds.isEmpty {
                        Text("No counters in this location")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(location.deviceIds, id: \.self) { deviceId in
                            HStack {
                                if isDeviceOffline(deviceId: deviceId) {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.red)
                                        .symbolRenderingMode(.hierarchical)
                                } else {
                                    Image(systemName: "wifi")
                                        .foregroundColor(.green)
                                }
                                VStack(alignment: .leading) {
                                    Text(deviceNickname(for: deviceId))
                                        .font(.body)
                                    Text(deviceId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                // Show warning if this counter is not on the map (only for map locations)
                                if location.isMapLocation && !mapDeviceIds.contains(deviceId) && deviceId != "Demo" {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // Warning about non-map counters (only for map locations)
                if location.isMapLocation {
                    let nonMapCounters = location.deviceIds.filter { !mapDeviceIds.contains($0) && $0 != "Demo" }
                    if !nonMapCounters.isEmpty {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(nonMapCounters.count) counter\(nonMapCounters.count == 1 ? " is" : "s are") not on the public map.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                // Daily Reset
                Section(header: Text("Daily Reset"), footer: Text("All counter counts will reset to 0 at this time every day. We recommend setting this during a time your location is closed or usually empty so that your total count doesn't shift over time.")) {
                    if isLoadingSchedule {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading schedule...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Toggle(isOn: $hasResetSchedule) {
                            Text("Enable Daily Reset")
                        }
                        .disabled(isSavingSchedule || location.deviceIds.isEmpty)
                        .onChange(of: hasResetSchedule) { _, newValue in
                            Task {
                                await handleScheduleToggleWithGroupCreation(enabled: newValue)
                            }
                        }

                        if hasResetSchedule {
                            DatePicker(
                                "Reset Time",
                                selection: $selectedResetTime,
                                displayedComponents: .hourAndMinute
                            )
                            .disabled(isSavingSchedule)
                            .onChange(of: selectedResetTime) { _, newValue in
                                if let groupId = location.overcrowdingGroupId {
                                    Task {
                                        await saveResetSchedule(groupId: groupId, time: newValue)
                                    }
                                }
                            }

                            Picker("Timezone", selection: $selectedTimezone) {
                                // Show device timezone first if not in common list
                                if !commonTimezones.contains(where: { $0.id == TimeZone.current.identifier }) {
                                    Text("Device (\(TimeZone.current.identifier))")
                                        .tag(TimeZone.current.identifier)
                                }
                                ForEach(commonTimezones, id: \.id) { tz in
                                    Text(tz.label).tag(tz.id)
                                }
                            }
                            .disabled(isSavingSchedule)
                            .onChange(of: selectedTimezone) { _, _ in
                                if let groupId = location.overcrowdingGroupId {
                                    Task {
                                        await saveResetSchedule(groupId: groupId, time: selectedResetTime)
                                    }
                                }
                            }
                        }
                    }
                }

                // Location Info
                Section(header: Text("Info"), footer: infoFooter) {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(location.isMapLocation ? "Live on Map" : "Local")
                            .foregroundColor(location.isMapLocation ? .green : .secondary)
                    }
                }

                // Folder Color
                Section(header: Text("Folder Color")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(CounterLocation.availableColors, id: \.name) { colorOption in
                            Button(action: {
                                selectedColor = colorOption.name
                                location.colorName = colorOption.name
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 36, height: 36)
                                    if selectedColor == colorOption.name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Appearance
                Section(header: Text("Appearance")) {
                    Button(action: {
                        appSettings.isDarkMode.toggle()
                    }) {
                        HStack {
                            Image(systemName: appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(appSettings.isDarkMode ? .yellow : .orange)
                            Text(appSettings.isDarkMode ? "Dark Mode" : "Light Mode")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("Press to Switch")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Reset All Counters
                Section(header: Text("Data Management"), footer: Text("This will permanently delete all history and count data for every counter in this location. This cannot be undone.")) {
                    Button(role: .destructive, action: {
                        showResetAllConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            if isResettingAll {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Resetting...")
                            } else {
                                Text("Reset All Counters' Data")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isResettingAll || location.deviceIds.isEmpty)
                }

                // Delete Location
                Section {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Delete Location")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Location Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationName = location.name
                selectedColor = location.colorName ?? "orange"
                // Load reset schedule if group exists
                print("[DailyReset] onAppear - local overcrowdingGroupId: \(location.overcrowdingGroupId ?? "nil")")
                print("[DailyReset] onAppear - deviceIds: \(location.deviceIds)")

                if let groupId = location.overcrowdingGroupId {
                    print("[DailyReset] Using local group ID: \(groupId)")
                    Task {
                        await loadResetSchedule(groupId: groupId)
                    }
                } else if !location.deviceIds.isEmpty {
                    // No local group ID - check server for existing group across all devices
                    print("[DailyReset] No local group ID, checking server...")
                    Task {
                        await checkForExistingGroup()
                    }
                } else {
                    print("[DailyReset] No devices in location, skipping")
                    isLoadingSchedule = false
                }
            }
            .alert("Delete Location?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will remove the location and all counters in it. You will need to re-add the counters if you want to use them again.")
            }
            .alert("Reset All Counters?", isPresented: $showResetAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset All", role: .destructive) {
                    Task {
                        await resetAllCounters()
                    }
                }
            } message: {
                Text("This will permanently delete all history and data for \(location.deviceIds.count) counter\(location.deviceIds.count == 1 ? "" : "s") in this location. This cannot be undone.")
            }
            .alert("Reset Result", isPresented: $showResetAllResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetAllResult ?? "")
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local: This location is only stored on this device.")
            Text("Live on Map: This location is visible on the public map with live count updates.")
        }
    }

    private func deviceNickname(for deviceId: String) -> String {
        NicknameManager.shared.displayName(for: deviceId)
    }

    private func isDeviceOffline(deviceId: String) -> Bool {
        // Find the user with this deviceId and check their offline status
        if let user = users.first(where: { $0.userId == deviceId }) {
            return isBluetoothSetupRequired[user.id] == true
        }
        return false
    }

    // MARK: - Reset Schedule Functions

    private func loadResetSchedule(groupId: String) async {
        print("[DailyReset] Loading reset schedule for group: \(groupId)")
        do {
            if let schedule = try await apiService.fetchResetSchedule(groupId: groupId) {
                print("[DailyReset] Found schedule: hour=\(schedule.resetHour), minute=\(schedule.resetMinute), timezone=\(schedule.timezone)")
                await MainActor.run {
                    hasResetSchedule = true
                    // Convert hour/minute to Date
                    if let time = Calendar.current.date(from: DateComponents(hour: schedule.resetHour, minute: schedule.resetMinute)) {
                        selectedResetTime = time
                    }
                    // Load saved timezone
                    selectedTimezone = schedule.timezone
                    isLoadingSchedule = false
                }
            } else {
                print("[DailyReset] No schedule found for group \(groupId)")
                await MainActor.run {
                    hasResetSchedule = false
                    // Default to device timezone for new schedules
                    selectedTimezone = TimeZone.current.identifier
                    isLoadingSchedule = false
                }
            }
        } catch {
            print("[DailyReset] Error loading reset schedule: \(error)")
            await MainActor.run {
                hasResetSchedule = false
                selectedTimezone = TimeZone.current.identifier
                isLoadingSchedule = false
            }
        }
    }

    private func checkForExistingGroup() async {
        // Check ALL devices in this location for existing group membership
        // This ensures any user with the same location devices can see existing reset schedules
        print("[DailyReset] Checking for existing group across \(location.deviceIds.count) devices: \(location.deviceIds)")

        for deviceIdToCheck in location.deviceIds {
            // Skip demo device
            if deviceIdToCheck == "Demo" {
                print("[DailyReset] Skipping Demo device")
                continue
            }

            do {
                print("[DailyReset] Checking device: \(deviceIdToCheck)")
                let groupIds = try await apiService.fetchGroupIdsForDevice(deviceId: deviceIdToCheck)
                print("[DailyReset] Device \(deviceIdToCheck) is in groups: \(groupIds)")

                if let existingGroupId = groupIds.first {
                    print("[DailyReset] Found existing group: \(existingGroupId)")
                    // Found existing group on server - update local state
                    await MainActor.run {
                        location.overcrowdingGroupId = existingGroupId
                    }
                    // Sync devices to ensure all current location devices are in the group
                    do {
                        try await apiService.updateOvercrowdingGroup(groupId: existingGroupId, deviceIds: location.deviceIds)
                        print("[DailyReset] Synced devices to group")
                    } catch {
                        print("[DailyReset] Error syncing group devices: \(error)")
                    }
                    await loadResetSchedule(groupId: existingGroupId)
                    return // Found a group, stop searching
                }
            } catch {
                print("[DailyReset] Error checking group for device \(deviceIdToCheck): \(error)")
                // Continue checking other devices
            }
        }

        // No existing group found for any device
        print("[DailyReset] No existing group found for any device")
        await MainActor.run {
            isLoadingSchedule = false
        }
    }

    private func handleScheduleToggle(enabled: Bool, groupId: String) async {
        if enabled {
            // Create new schedule with current selected time
            await saveResetSchedule(groupId: groupId, time: selectedResetTime)
        } else {
            // Delete existing schedule
            await deleteSchedule(groupId: groupId)
        }
    }

    private func handleScheduleToggleWithGroupCreation(enabled: Bool) async {
        if enabled {
            // If no group exists, create one first
            if location.overcrowdingGroupId == nil {
                await MainActor.run {
                    isSavingSchedule = true
                }

                do {
                    // Create a group with limit 0 (just for reset scheduling, no overcrowding alert)
                    let groupId = try await apiService.createOvercrowdingGroup(
                        deviceIds: location.deviceIds,
                        limit: 0,
                        groupName: location.name
                    )

                    await MainActor.run {
                        location.overcrowdingGroupId = groupId
                    }

                    // Now create the schedule
                    await saveResetSchedule(groupId: groupId, time: selectedResetTime)
                } catch {
                    print("Error creating group for reset schedule: \(error)")
                    await MainActor.run {
                        hasResetSchedule = false
                        isSavingSchedule = false
                    }
                }
            } else {
                // Group exists - sync devices to match current location, then create/update schedule
                let groupId = location.overcrowdingGroupId!
                do {
                    try await apiService.updateOvercrowdingGroup(groupId: groupId, deviceIds: location.deviceIds)
                } catch {
                    print("Error syncing group devices: \(error)")
                }
                await saveResetSchedule(groupId: groupId, time: selectedResetTime)
            }
        } else {
            // Disable - delete the schedule
            if let groupId = location.overcrowdingGroupId {
                await deleteSchedule(groupId: groupId)
            }
        }
    }

    private func saveResetSchedule(groupId: String, time: Date) async {
        guard hasResetSchedule else { return }

        await MainActor.run {
            isSavingSchedule = true
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 6
        let minute = components.minute ?? 0

        do {
            _ = try await apiService.setResetSchedule(groupId: groupId, hour: hour, minute: minute, timezone: selectedTimezone)
            await MainActor.run {
                isSavingSchedule = false
            }
        } catch {
            print("Error saving reset schedule: \(error)")
            await MainActor.run {
                isSavingSchedule = false
            }
        }
    }

    private func deleteSchedule(groupId: String) async {
        await MainActor.run {
            isSavingSchedule = true
        }

        do {
            try await apiService.deleteResetSchedule(groupId: groupId)
            await MainActor.run {
                isSavingSchedule = false
            }
        } catch {
            print("Error deleting reset schedule: \(error)")
            await MainActor.run {
                isSavingSchedule = false
            }
        }
    }

    // MARK: - Reset All Counters

    private func resetAllCounters() async {
        await MainActor.run {
            isResettingAll = true
        }

        var successCount = 0
        var missingCredentials: [String] = []
        var apiErrors: [String] = []

        for deviceId in location.deviceIds {
            // Skip demo device
            if deviceId == "Demo" {
                continue
            }

            // Find the user and their password
            guard let user = users.first(where: { $0.userId == deviceId }),
                  let password = userPasswords[user.id] else {
                missingCredentials.append(NicknameManager.shared.displayName(for: deviceId))
                continue
            }

            // Call reset endpoint
            let success = await resetDeviceData(deviceId: deviceId, password: password)
            if success {
                successCount += 1
            } else {
                apiErrors.append(NicknameManager.shared.displayName(for: deviceId))
            }
        }

        let failCount = missingCredentials.count + apiErrors.count

        await MainActor.run {
            isResettingAll = false

            var lines: [String] = []

            if successCount > 0 {
                lines.append("Successfully reset \(successCount) counter\(successCount == 1 ? "" : "s").")
            }

            if !missingCredentials.isEmpty {
                lines.append("Missing credentials for: \(missingCredentials.joined(separator: ", ")). Try logging out and back in.")
            }

            if !apiErrors.isEmpty {
                lines.append("Server error for: \(apiErrors.joined(separator: ", ")). Check your connection and try again.")
            }

            if failCount == 0 && successCount == 0 {
                lines.append("No counters to reset.")
            }

            resetAllResult = lines.joined(separator: "\n\n")
            showResetAllResult = true

            if successCount > 0 {
                onCountsReset?()
            }
        }
    }

    private func resetDeviceData(deviceId: String, password: String) async -> Bool {
        guard let url = URL(string: "\(serverURL)/reset_device_data") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": deviceId, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
            return false
        } catch {
            print("Error resetting device \(deviceId): \(error)")
            return false
        }
    }
}

#Preview {
    LocationSettingsView(
        location: .constant(CounterLocation(
            id: UUID(),
            name: "Grand Central",
            deviceIds: ["T0001", "T0002"],
            overcrowdingLimit: 2000,
            isMapLocation: true,
            mapPrimaryDevice: "T0001"
        )),
        users: [],
        onSave: {},
        onDelete: {},
        mapDeviceIds: ["T0001"],  // T0002 will show warning
        isBluetoothSetupRequired: [:],
        userPasswords: [:],
        serverURL: "https://api.crowdcount.tech"
    )
}
