import SwiftUI

struct LocationSettingsView: View {
    @Binding var location: AppLocation
    let devices: [Device]
    let deviceStatuses: [String: String]
    let onSave: (AppLocation) -> Void
    let onDelete: () -> Void
    var removeDeviceFromLocation: ((String) async -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appSettings: AppSettings
    @State private var locationName: String = ""
    @State private var originalName: String = ""
    @State private var selectedColor: String = "orange"
    @State private var showDeleteConfirmation: Bool = false
    @State private var deviceToRemove: String? = nil
    @State private var showRemoveDeviceConfirmation: Bool = false

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

    /// Credentials for API calls
    private var credentials: [[String: String]] {
        devices.filter { location.deviceIds.contains($0.deviceId) }
            .map { ["device_id": $0.deviceId, "password": $0.password] }
    }

    private var signingDevice: (String, String)? {
        guard let first = devices.first(where: { location.deviceIds.contains($0.deviceId) }) else { return nil }
        return (first.deviceId, first.password)
    }

    var body: some View {
        NavigationView {
            Form {
                // Location Name
                Section(header: Text("Location Name"), footer: location.isOnMap ? Text("Name is synced from the public map. Email info@crowdcount.tech to request changes.") : nil) {
                    if location.isOnMap {
                        Text(locationName)
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Location name", text: $locationName)
                    }
                }

                // Map Status
                Section(header: Text("Map Status")) {
                    if location.isOnMap {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.green)
                            Text("Live on Map")
                                .foregroundColor(.primary)
                        }
                    } else {
                        NavigationLink(destination: GetOnMapInfoView()) {
                            HStack {
                                Image(systemName: "mappin.slash")
                                    .foregroundColor(.secondary)
                                Text("Not on Map")
                                    .foregroundColor(.primary)
                            }
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
                                let isOffline = deviceStatuses[deviceId] != "online"
                                Image(systemName: isOffline ? "wifi.slash" : "wifi")
                                    .foregroundColor(isOffline ? .red : .green)
                                    .symbolRenderingMode(.hierarchical)
                                VStack(alignment: .leading) {
                                    Text(NicknameManager.shared.displayName(for: deviceId))
                                        .font(.body)
                                    Text(deviceId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if removeDeviceFromLocation != nil {
                                    Button(role: .destructive) {
                                        deviceToRemove = deviceId
                                        showRemoveDeviceConfirmation = true
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                    }
                                }
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
                                await handleScheduleToggle(enabled: newValue)
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
                                Task {
                                    await saveResetSchedule(time: newValue)
                                }
                            }

                            Picker("Timezone", selection: $selectedTimezone) {
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
                                Task {
                                    await saveResetSchedule(time: selectedResetTime)
                                }
                            }
                        }
                    }
                }

                // Folder Color (only for non-map locations)
                if !location.isOnMap {
                    Section(header: Text("Folder Color")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                            ForEach(AppLocation.availableColors, id: \.name) { colorOption in
                                Button(action: {
                                    selectedColor = colorOption.name
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

                // Reset Location Data
                Section(header: Text("Data Management"), footer: Text("This will permanently delete all history and count data for this location. Individual counter data will not be affected. This cannot be undone.")) {
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
                                Text("Reset Location Data")
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
                        // Apply all local edits to the location
                        var updated = location
                        if !location.isOnMap && locationName != originalName {
                            updated.name = locationName
                            if let signing = signingDevice {
                                Task {
                                    try? await apiService.updateLocation(
                                        locationId: location.id,
                                        name: locationName,
                                        credentials: credentials,
                                        signingDevice: signing
                                    )
                                }
                            }
                        }
                        updated.colorName = selectedColor
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationName = location.name
                originalName = location.name
                selectedColor = location.colorName ?? "orange"
                loadResetSchedule()
            }
            .alert("Delete Location?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will remove the location. You will need to re-add the counters if you want to use them again.")
            }
            .alert("Reset Location Data?", isPresented: $showResetAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    Task {
                        await resetLocationData()
                    }
                }
            } message: {
                Text("This will permanently delete all history and count data for this location. This cannot be undone.")
            }
            .alert("Reset Result", isPresented: $showResetAllResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetAllResult ?? "")
            }
            .alert("Remove Counter?", isPresented: $showRemoveDeviceConfirmation) {
                Button("Cancel", role: .cancel) {
                    deviceToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    if let deviceId = deviceToRemove, let remove = removeDeviceFromLocation {
                        Task {
                            await remove(deviceId)
                            dismiss()
                        }
                        deviceToRemove = nil
                    }
                }
            } message: {
                if let deviceId = deviceToRemove {
                    Text("Remove \(NicknameManager.shared.displayName(for: deviceId)) from this location? You will need to re-add it if you want to use it again.")
                }
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    // MARK: - Reset Schedule

    private func loadResetSchedule() {
        guard !location.deviceIds.isEmpty, let signing = signingDevice else {
            isLoadingSchedule = false
            return
        }

        // Use the location_id to fetch reset schedule from server
        Task {
            do {
                if let schedule = try await apiService.fetchResetSchedule(locationId: location.id, credentials: credentials, signingDevice: signing) {
                    await MainActor.run {
                        hasResetSchedule = true
                        if let time = Calendar.current.date(from: DateComponents(hour: schedule.resetHour, minute: schedule.resetMinute)) {
                            selectedResetTime = time
                        }
                        selectedTimezone = schedule.timezone
                        isLoadingSchedule = false
                    }
                } else {
                    await MainActor.run {
                        hasResetSchedule = false
                        selectedTimezone = TimeZone.current.identifier
                        isLoadingSchedule = false
                    }
                }
            } catch {
                print("Error loading reset schedule: \(error)")
                await MainActor.run {
                    hasResetSchedule = false
                    selectedTimezone = TimeZone.current.identifier
                    isLoadingSchedule = false
                }
            }
        }
    }

    private func handleScheduleToggle(enabled: Bool) async {
        if enabled {
            await saveResetSchedule(time: selectedResetTime)
        } else {
            await deleteSchedule()
        }
    }

    private func saveResetSchedule(time: Date) async {
        guard hasResetSchedule, let signing = signingDevice else { return }

        await MainActor.run {
            isSavingSchedule = true
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 6
        let minute = components.minute ?? 0

        do {
            _ = try await apiService.setResetSchedule(
                locationId: location.id,
                hour: hour,
                minute: minute,
                timezone: selectedTimezone,
                credentials: credentials,
                signingDevice: signing
            )
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

    private func deleteSchedule() async {
        guard let signing = signingDevice else { return }

        await MainActor.run {
            isSavingSchedule = true
        }

        do {
            try await apiService.deleteResetSchedule(
                locationId: location.id,
                credentials: credentials,
                signingDevice: signing
            )
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

    // MARK: - Reset Location Data

    private func resetLocationData() async {
        guard let signing = signingDevice else { return }

        await MainActor.run {
            isResettingAll = true
        }

        do {
            try await apiService.resetLocationData(
                locationId: location.id,
                credentials: credentials,
                signingDevice: signing
            )
            await MainActor.run {
                isResettingAll = false
                resetAllResult = "Location data reset successfully."
                showResetAllResult = true
            }
        } catch {
            print("Error resetting location data: \(error)")
            await MainActor.run {
                isResettingAll = false
                resetAllResult = "Failed to reset location data. Check your connection and try again."
                showResetAllResult = true
            }
        }
    }
}
