import SwiftUI

struct LocationSettingsView: View {
    @Binding var location: AppLocation
    let devices: [Device]
    let deviceStatuses: [String: String]
    let onSave: (AppLocation) -> Void
    let onDelete: () -> Void
    var removeDeviceFromLocation: ((String) async -> Void)? = nil
    var isClosed: Bool = false

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appSettings: AppSettings
    @State private var locationName: String = ""
    @State private var originalName: String = ""
    @State private var selectedColor: String = "orange"
    @State private var showDeleteConfirmation: Bool = false
    @State private var deviceToRemove: String? = nil
    @State private var showRemoveDeviceConfirmation: Bool = false

    // Daily Reset state
//    @State private var hasResetSchedule: Bool = false
//    @State private var selectedResetTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
//    @State private var selectedTimezone: String = TimeZone.current.identifier
//    @State private var isLoadingSchedule: Bool = true
//    @State private var isSavingSchedule: Bool = false
    private let apiService = APIService.shared

    // Reset All Counters state
    @State private var showResetAllConfirmation: Bool = false
    @State private var isResettingAll: Bool = false
    @State private var resetAllResult: String? = nil
    @State private var showResetAllResult: Bool = false

    // POS state
    @State private var posStatus: POSConnectionInfo?
    @State private var isLoadingPOS: Bool = true
    @State private var showPOSConnectSheet: Bool = false
    @State private var showPOSDisconnectConfirmation: Bool = false
    @State private var posDisconnecting: Bool = false

    // Operating Hours state
    @State private var hasClosingTime: Bool = false
    @State private var isLoadingClosingTime: Bool = true
    @State private var isSavingClosingTime: Bool = false
    @State private var closingTimeClose: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @State private var closingTimeOpen: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
    @State private var closingTimeTimezone: String = TimeZone.current.identifier
    @State private var isAdvancedClosingTime: Bool = false
    @State private var closingTimeDays: [ClosingTimeDayState] = ClosingTimeDayState.defaultWeek()

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
            formContent
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
                // loadResetSchedule()
                loadClosingTime()
                loadPOSStatus()
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
            .alert("Disconnect POS?", isPresented: $showPOSDisconnectConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    Task { await disconnectPOS() }
                }
            } message: {
                Text("This will disconnect the POS system from this location. Sales data will no longer be synced.")
            }
            .sheet(isPresented: $showPOSConnectSheet) {
                POSConnectView(
                    locationId: location.id,
                    locationName: location.name,
                    credentials: credentials,
                    signingDevice: signingDevice ?? ("", ""),
                    onConnected: {
                        loadPOSStatus()
                    }
                )
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

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
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

            countersSection

            posSection

            // dailyResetSection

            closingTimeSection

            folderColorSection

            appearanceSection

            dataManagementSection

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
    }

    // MARK: - Counters Section

    @ViewBuilder
    private var countersSection: some View {
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
    }

    // MARK: - POS Section

    @ViewBuilder
    private var posSection: some View {
        Section(header: Text("Point of Sale"),
                footer: Text(posStatus?.connected == true
                    ? "Sales data is synced from your POS system"
                    : "Connect a POS to see sales data alongside foot traffic")) {
            if isLoadingPOS {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Loading POS status...")
                        .foregroundColor(.secondary)
                }
            } else if let pos = posStatus, pos.connected {
                // Connected state
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pos.provider?.rawValue.capitalized ?? "POS") — \"\(pos.posLocationName ?? "Unknown")\"")
                            .font(.body)
                        if let connectedAt = pos.connectedAt {
                            Text("Connected \(connectedAt)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Disconnect
                Button(role: .destructive) {
                    showPOSDisconnectConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text(posDisconnecting ? "Disconnecting..." : "Disconnect")
                    }
                }
                .disabled(posDisconnecting)
            } else {
                // Disconnected state
                Button {
                    showPOSConnectSheet = true
                } label: {
                    HStack {
                        Image(systemName: "creditcard.and.123")
                            .foregroundColor(.blue)
                        Text("Connect POS")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    // MARK: - POS Actions

    private func loadPOSStatus() {
        isLoadingPOS = true
        Task {
            // Always fetch fresh from server to ensure up-to-date status
            guard let signing = signingDevice else {
                // Fall back to cache if no signing device
                posStatus = POSStatusManager.shared.getStatus(for: location.id)
                isLoadingPOS = false
                return
            }
            await POSStatusManager.shared.refreshStatus(
                for: location.id,
                credentials: credentials,
                signingDevice: signing
            )
            posStatus = POSStatusManager.shared.getStatus(for: location.id)
            isLoadingPOS = false
        }
    }

    private func disconnectPOS() async {
        guard let signing = signingDevice else { return }
        posDisconnecting = true
        do {
            _ = try await apiService.disconnectPOS(
                locationId: location.id,
                credentials: credentials,
                signingDevice: signing
            )
            POSStatusManager.shared.clearStatus(for: location.id)
            posStatus = nil
        } catch {
            // Silently handle
        }
        posDisconnecting = false
    }

    // MARK: - Folder Color Section

    @ViewBuilder
    private var folderColorSection: some View {
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
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private var appearanceSection: some View {
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
    }

    // MARK: - Data Management Section

    @ViewBuilder
    private var dataManagementSection: some View {
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
    }

    // MARK: - Operating Hours Section

    @ViewBuilder
    private var closingTimeSection: some View {
        Section(header: Text("Operating Hours"), footer: Text("Set when your location opens and closes. Outside operating hours, counts will be paused and the counter will show \"Closed\".")) {
            if isLoadingClosingTime {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading closing time...")
                        .foregroundColor(.secondary)
                }
            } else {
                Toggle(isOn: $hasClosingTime) {
                    Text("Enable Operating Hours")
                }
                .disabled(isSavingClosingTime || location.deviceIds.isEmpty)
                .onChange(of: hasClosingTime) { _, newValue in
                    Task {
                        await handleClosingTimeToggle(enabled: newValue)
                    }
                }

                if hasClosingTime {
                    closingTimeDetails
                }
            }
        }
    }

    @ViewBuilder
    private var closingTimeDetails: some View {
        if !isAdvancedClosingTime {
            DatePicker(
                "Opens at",
                selection: $closingTimeOpen,
                displayedComponents: .hourAndMinute
            )
            .disabled(isSavingClosingTime)
            .onChange(of: closingTimeOpen) { _, _ in
                Task { await saveClosingTime() }
            }

            DatePicker(
                "Closes at",
                selection: $closingTimeClose,
                displayedComponents: .hourAndMinute
            )
            .disabled(isSavingClosingTime)
            .onChange(of: closingTimeClose) { _, _ in
                Task { await saveClosingTime() }
            }
        }

        Toggle(isOn: $isAdvancedClosingTime) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Text("Per-day schedule")
            }
        }
        .disabled(isSavingClosingTime)
        .onChange(of: isAdvancedClosingTime) { _, newValue in
            if newValue {
                for i in closingTimeDays.indices {
                    closingTimeDays[i].isEnabled = true
                    closingTimeDays[i].closeTime = closingTimeClose
                    closingTimeDays[i].openTime = closingTimeOpen
                }
            }
            Task { await saveClosingTime() }
        }

        if isAdvancedClosingTime {
            closingTimeDayRows
        }

        Picker("Timezone", selection: $closingTimeTimezone) {
            if !commonTimezones.contains(where: { $0.id == TimeZone.current.identifier }) {
                Text("Device (\(TimeZone.current.identifier))")
                    .tag(TimeZone.current.identifier)
            }
            ForEach(commonTimezones, id: \.id) { tz in
                Text(tz.label).tag(tz.id)
            }
        }
        .disabled(isSavingClosingTime)
        .onChange(of: closingTimeTimezone) { _, _ in
            Task { await saveClosingTime() }
        }

        HStack {
            Image(systemName: isClosed ? "moon.fill" : "sun.max.fill")
                .foregroundColor(isClosed ? .orange : .green)
            Text(isClosed ? "Currently Closed" : "Currently Open")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var closingTimeDayRows: some View {
        ForEach($closingTimeDays) { $day in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(day.label)
                        .fontWeight(.medium)
                    Spacer()
                    if day.isEnabled {
                        Text(closingTimeSummary(open: day.openTime, close: day.closeTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Toggle("", isOn: $day.isEnabled)
                        .labelsHidden()
                        .disabled(isSavingClosingTime)
                        .onChange(of: day.isEnabled) { _, _ in
                            Task { await saveClosingTime() }
                        }
                }

                if day.isEnabled {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker(
                                "",
                                selection: $day.openTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .disabled(isSavingClosingTime)
                            .onChange(of: day.openTime) { _, _ in
                                Task { await saveClosingTime() }
                            }
                        }

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Close")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker(
                                "",
                                selection: $day.closeTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .disabled(isSavingClosingTime)
                            .onChange(of: day.closeTime) { _, _ in
                                Task { await saveClosingTime() }
                            }
                        }

                        Spacer()
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func closingTimeSummary(open: Date, close: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: open)) - \(formatter.string(from: close))"
    }

    // MARK: - Reset Schedule (commented out)

//    private var dailyResetSection: some View {
//        Section(header: Text("Daily Reset"), footer: Text("All counter counts will reset to 0 at this time every day.")) {
//            if isLoadingSchedule {
//                HStack {
//                    ProgressView().scaleEffect(0.8)
//                    Text("Loading schedule...").foregroundColor(.secondary)
//                }
//            } else {
//                Toggle(isOn: $hasResetSchedule) { Text("Enable Daily Reset") }
//                    .disabled(isSavingSchedule || location.deviceIds.isEmpty)
//                    .onChange(of: hasResetSchedule) { _, newValue in
//                        Task { await handleScheduleToggle(enabled: newValue) }
//                    }
//                if hasResetSchedule {
//                    DatePicker("Reset Time", selection: $selectedResetTime, displayedComponents: .hourAndMinute)
//                        .disabled(isSavingSchedule)
//                        .onChange(of: selectedResetTime) { _, newValue in
//                            Task { await saveResetSchedule(time: newValue) }
//                        }
//                    Picker("Timezone", selection: $selectedTimezone) {
//                        if !commonTimezones.contains(where: { $0.id == TimeZone.current.identifier }) {
//                            Text("Device (\(TimeZone.current.identifier))").tag(TimeZone.current.identifier)
//                        }
//                        ForEach(commonTimezones, id: \.id) { tz in Text(tz.label).tag(tz.id) }
//                    }
//                    .disabled(isSavingSchedule)
//                    .onChange(of: selectedTimezone) { _, _ in
//                        Task { await saveResetSchedule(time: selectedResetTime) }
//                    }
//                }
//            }
//        }
//    }
//
//    private func loadResetSchedule() {
//        guard !location.deviceIds.isEmpty, let signing = signingDevice else {
//            isLoadingSchedule = false
//            return
//        }
//        Task {
//            do {
//                if let schedule = try await apiService.fetchResetSchedule(locationId: location.id, credentials: credentials, signingDevice: signing) {
//                    hasResetSchedule = true
//                    if let time = Calendar.current.date(from: DateComponents(hour: schedule.resetHour, minute: schedule.resetMinute)) {
//                        selectedResetTime = time
//                    }
//                    selectedTimezone = schedule.timezone
//                } else {
//                    hasResetSchedule = false
//                    selectedTimezone = TimeZone.current.identifier
//                }
//            } catch {
//                hasResetSchedule = false
//                selectedTimezone = TimeZone.current.identifier
//            }
//            isLoadingSchedule = false
//        }
//    }
//
//    private func handleScheduleToggle(enabled: Bool) async {
//        if enabled { await saveResetSchedule(time: selectedResetTime) } else { await deleteSchedule() }
//    }
//
//    private func saveResetSchedule(time: Date) async {
//        guard hasResetSchedule, let signing = signingDevice else { return }
//        isSavingSchedule = true
//        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
//        do {
//            _ = try await apiService.setResetSchedule(locationId: location.id, hour: components.hour ?? 6, minute: components.minute ?? 0, timezone: selectedTimezone, credentials: credentials, signingDevice: signing)
//        } catch { }
//        isSavingSchedule = false
//    }
//
//    private func deleteSchedule() async {
//        guard let signing = signingDevice else { return }
//        isSavingSchedule = true
//        do {
//            try await apiService.deleteResetSchedule(locationId: location.id, credentials: credentials, signingDevice: signing)
//        } catch { }
//        isSavingSchedule = false
//    }

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

    // MARK: - Operating Hours

    private func loadClosingTime() {
        guard !location.deviceIds.isEmpty, let signing = signingDevice else {
            isLoadingClosingTime = false
            return
        }

        Task {
            do {
                if let schedule = try await apiService.fetchClosingTime(locationId: location.id, credentials: credentials, signingDevice: signing) {
                    await MainActor.run {
                        hasClosingTime = true
                        closingTimeTimezone = schedule.timezone

                        // Check if all days have the same times (simple mode)
                        let allSame = schedule.days.count == 7 &&
                            Set(schedule.days.map { "\($0.closeHour):\($0.closeMinute)-\($0.openHour):\($0.openMinute)" }).count == 1

                        if allSame, let first = schedule.days.first {
                            isAdvancedClosingTime = false
                            if let close = Calendar.current.date(from: DateComponents(hour: first.closeHour, minute: first.closeMinute)) {
                                closingTimeClose = close
                            }
                            if let open = Calendar.current.date(from: DateComponents(hour: first.openHour, minute: first.openMinute)) {
                                closingTimeOpen = open
                            }
                        } else {
                            isAdvancedClosingTime = true
                        }

                        // Populate per-day state
                        for i in closingTimeDays.indices {
                            if let serverDay = schedule.days.first(where: { $0.dayOfWeek == closingTimeDays[i].id }) {
                                closingTimeDays[i].isEnabled = true
                                if let close = Calendar.current.date(from: DateComponents(hour: serverDay.closeHour, minute: serverDay.closeMinute)) {
                                    closingTimeDays[i].closeTime = close
                                }
                                if let open = Calendar.current.date(from: DateComponents(hour: serverDay.openHour, minute: serverDay.openMinute)) {
                                    closingTimeDays[i].openTime = open
                                }
                            } else {
                                closingTimeDays[i].isEnabled = false
                            }
                        }

                        isLoadingClosingTime = false
                    }
                } else {
                    await MainActor.run {
                        hasClosingTime = false
                        closingTimeTimezone = TimeZone.current.identifier
                        isLoadingClosingTime = false
                    }
                }
            } catch {
                print("Error loading closing time: \(error)")
                await MainActor.run {
                    hasClosingTime = false
                    closingTimeTimezone = TimeZone.current.identifier
                    isLoadingClosingTime = false
                }
            }
        }
    }

    private func handleClosingTimeToggle(enabled: Bool) async {
        if enabled {
            await saveClosingTime()
        } else {
            await deleteClosingTime()
        }
    }

    private func saveClosingTime() async {
        guard hasClosingTime, let signing = signingDevice else { return }

        await MainActor.run {
            isSavingClosingTime = true
        }

        var days: [APIService.ClosingTimeDay] = []

        if isAdvancedClosingTime {
            for day in closingTimeDays where day.isEnabled {
                let closeComps = Calendar.current.dateComponents([.hour, .minute], from: day.closeTime)
                let openComps = Calendar.current.dateComponents([.hour, .minute], from: day.openTime)
                days.append(APIService.ClosingTimeDay(
                    dayOfWeek: day.id,
                    closeHour: closeComps.hour ?? 22,
                    closeMinute: closeComps.minute ?? 0,
                    openHour: openComps.hour ?? 6,
                    openMinute: openComps.minute ?? 0
                ))
            }
        } else {
            // Simple mode: same time every day
            let closeComps = Calendar.current.dateComponents([.hour, .minute], from: closingTimeClose)
            let openComps = Calendar.current.dateComponents([.hour, .minute], from: closingTimeOpen)
            for dayIndex in 0...6 {
                days.append(APIService.ClosingTimeDay(
                    dayOfWeek: dayIndex,
                    closeHour: closeComps.hour ?? 22,
                    closeMinute: closeComps.minute ?? 0,
                    openHour: openComps.hour ?? 6,
                    openMinute: openComps.minute ?? 0
                ))
            }
        }

        // Must have at least one day
        guard !days.isEmpty else {
            await MainActor.run {
                isSavingClosingTime = false
            }
            return
        }

        do {
            _ = try await apiService.setClosingTime(
                locationId: location.id,
                timezone: closingTimeTimezone,
                days: days,
                credentials: credentials,
                signingDevice: signing
            )
            await MainActor.run {
                isSavingClosingTime = false
            }
        } catch {
            print("Error saving closing time: \(error)")
            await MainActor.run {
                isSavingClosingTime = false
            }
        }
    }

    private func deleteClosingTime() async {
        guard let signing = signingDevice else { return }

        await MainActor.run {
            isSavingClosingTime = true
        }

        do {
            try await apiService.deleteClosingTime(
                locationId: location.id,
                credentials: credentials,
                signingDevice: signing
            )
            await MainActor.run {
                isSavingClosingTime = false
            }
        } catch {
            print("Error deleting closing time: \(error)")
            await MainActor.run {
                isSavingClosingTime = false
            }
        }
    }
}

// MARK: - Operating Hours Day State

struct ClosingTimeDayState: Identifiable {
    let id: Int          // day_of_week 0-6
    let label: String    // "Monday" ... "Sunday"
    var isEnabled: Bool
    var closeTime: Date
    var openTime: Date

    static func defaultWeek() -> [ClosingTimeDayState] {
        let labels = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let defaultClose = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        let defaultOpen = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
        return (0..<7).map { i in
            ClosingTimeDayState(id: i, label: labels[i], isEnabled: true, closeTime: defaultClose, openTime: defaultOpen)
        }
    }
}
