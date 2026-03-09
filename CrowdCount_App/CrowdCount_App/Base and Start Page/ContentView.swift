import SwiftUI
import Network
import UIKit

// MARK: - Data Models

struct Device: Identifiable, Codable {
    let id: UUID              // Local SwiftUI identity
    let deviceId: String      // Server device ID (e.g. "T1234")
    let password: String      // Stored per-device
}

struct AppLocation: Identifiable, Codable, Hashable {
    let id: String            // Server location_id (UUID string)
    var name: String
    var deviceIds: [String]
    var overcrowdingLimit: Int?
    var colorName: String?
    var isOvercrowdingNotificationEnabled: Bool
    var isOnMap: Bool
    var mapIcon: String?
    var mapColor: String?

    init(id: String, name: String, deviceIds: [String], overcrowdingLimit: Int? = nil, colorName: String? = nil, isOvercrowdingNotificationEnabled: Bool = false, isOnMap: Bool = false, mapIcon: String? = nil, mapColor: String? = nil) {
        self.id = id
        self.name = name
        self.deviceIds = deviceIds
        self.overcrowdingLimit = overcrowdingLimit
        self.colorName = colorName
        self.isOvercrowdingNotificationEnabled = isOvercrowdingNotificationEnabled
        self.isOnMap = isOnMap
        self.mapIcon = mapIcon
        self.mapColor = mapColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        deviceIds = try container.decode([String].self, forKey: .deviceIds)
        overcrowdingLimit = try container.decodeIfPresent(Int.self, forKey: .overcrowdingLimit)
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
        isOvercrowdingNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isOvercrowdingNotificationEnabled) ?? false
        isOnMap = try container.decodeIfPresent(Bool.self, forKey: .isOnMap) ?? false
        mapIcon = try container.decodeIfPresent(String.self, forKey: .mapIcon)
        mapColor = try container.decodeIfPresent(String.self, forKey: .mapColor)
    }

    // Available colors for folder icons (rainbow order)
    static let availableColors: [(name: String, color: Color)] = [
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("blue", .blue),
        ("purple", .purple)
    ]

    var folderColor: Color {
        if let colorName = colorName,
           let match = Self.availableColors.first(where: { $0.name == colorName }) {
            return match.color
        }
        return .orange  // Default
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AppLocation, rhs: AppLocation) -> Bool {
        lhs.id == rhs.id
        && lhs.name == rhs.name
        && lhs.deviceIds == rhs.deviceIds
        && lhs.overcrowdingLimit == rhs.overcrowdingLimit
        && lhs.colorName == rhs.colorName
        && lhs.isOnMap == rhs.isOnMap
        && lhs.isOvercrowdingNotificationEnabled == rhs.isOvercrowdingNotificationEnabled
        && lhs.mapIcon == rhs.mapIcon
        && lhs.mapColor == rhs.mapColor
    }
}

struct IncompleteLocationWarning: Identifiable {
    let id: String               // server location_id (dedup key)
    let serverLocationName: String
    let totalDeviceCount: Int
    let missingDeviceIds: [String]
    let userDeviceIds: [String]  // which of the user's devices are in this location
}

// MARK: - ContentView

struct ContentView: View {
    // MARK: - State
    @State private var devices: [Device] = []
    @State private var locations: [AppLocation] = []
    @State private var locationCounts: [String: Int] = [:]    // locationId → count
    @State private var locationClosedStates: [String: Bool] = [:] // locationId → is closed
    @State private var deviceCounts: [String: Int] = [:]      // deviceId → count
    @State private var deviceStatuses: [String: String] = [:] // deviceId → "online"/"offline"
    @State private var viewingLocationId: String? = UserDefaults.standard.string(forKey: "cc_lastViewingLocationId")
    @State private var showLoginScreen: Bool = true
    @State private var showLocationList: Bool = false
    @State private var isServerRunning: Bool = false
    @State private var serverStatus: String = "Loading..."
    @State private var serverStatusColor: Color = .gray
    @State private var countPollingTimer: Timer?
    @State private var statusPollingTimer: Timer?
    @State private var serverStatusTimer: Timer?
    @State private var heartbeatTimer: Timer?
    @State private var lastManualCountChange: [String: Date] = [:]  // locationId → timestamp (grace period after +/-)
    @State private var showReconciliationAlert: Bool = false
    @State private var reconciliationMessage: String = ""

    // Login fields
    @State private var userId: String = ""
    @State private var password: String = ""
    @State private var locationName: String = ""
    @State private var errorMessage: String?
    @State private var isLoggingIn: Bool = false
    @State private var additionalCounters: [CounterEntry] = []

    @State private var incompleteLocationWarnings: [IncompleteLocationWarning] = []
    @State private var dismissedIncompleteWarnings: Set<String> = {
        let arr = UserDefaults.standard.stringArray(forKey: "cc_dismissed_incomplete_warnings") ?? []
        return Set(arr)
    }()

    @State private var path = NavigationPath()
    @StateObject private var alertViewModel = AlertViewModel()

    private let apiService = APIService.shared
    let networkMonitor = NetworkMonitor.shared

    @EnvironmentObject var appSettings: AppSettings
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let serverURL = AppSettings.apiBaseURL

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BlurredEdgesViewRepresentable(
                    edgeColor: .label,
                    edgeThickness: 10
                ).edgesIgnoringSafeArea(.all)

                VisualEffectView(
                    effect: UIBlurEffect(style: .regular)
                ).edgesIgnoringSafeArea(.all)

                VStack {
                    if !isServerRunning {
                        ServerStatusView(serverStatus: serverStatus, serverStatusColor: serverStatusColor)
                    } else if showLoginScreen {
                        LoginView(
                            userId: $userId,
                            password: $password,
                            locationName: $locationName,
                            errorMessage: $errorMessage,
                            isLoggingIn: $isLoggingIn,
                            additionalCounters: $additionalCounters,
                            setUser: setUser,
                            serverStatus: serverStatus,
                            serverStatusColor: serverStatusColor,
                            alertViewModel: alertViewModel
                        )
                    } else {
                        if locations.isEmpty {
                            LoginView(
                                userId: $userId,
                                password: $password,
                                locationName: $locationName,
                                errorMessage: $errorMessage,
                                isLoggingIn: $isLoggingIn,
                                additionalCounters: $additionalCounters,
                                setUser: setUser,
                                serverStatus: serverStatus,
                                serverStatusColor: serverStatusColor,
                                alertViewModel: alertViewModel
                            )
                        } else if let locationId = viewingLocationId,
                                  let currentLocation = locations.first(where: { $0.id == locationId }) {
                            LocationCountersView(
                                location: currentLocation,
                                currentCount: locationCounts[locationId] ?? 0,
                                isClosed: locationClosedStates[locationId] ?? false,
                                devices: devices,
                                deviceStatuses: $deviceStatuses,
                                locations: $locations,
                                viewingLocationId: $viewingLocationId,
                                showLoginScreen: $showLoginScreen,
                                alertViewModel: alertViewModel,
                                incompleteLocationWarnings: incompleteLocationWarnings.filter { warning in
                                    !dismissedIncompleteWarnings.contains("\(warning.id)_\(warning.totalDeviceCount)")
                                },
                                onDismissIncompleteWarning: { warningId, deviceCount in
                                    let key = "\(warningId)_\(deviceCount)"
                                    dismissedIncompleteWarnings.insert(key)
                                    UserDefaults.standard.set(Array(dismissedIncompleteWarnings), forKey: "cc_dismissed_incomplete_warnings")
                                },
                                addToCount: { amount in addToCount(locationId: locationId, amount: amount) },
                                subFromCount: { amount in subFromCount(locationId: locationId, amount: amount) },
                                addDeviceToLocation: { deviceId, pw, label in
                                    await addDeviceToLocationAsync(locationId: locationId, newDeviceId: deviceId, password: pw, label: label)
                                },
                                removeDeviceFromLocation: { deviceId in
                                    await removeDeviceFromLocationAsync(locationId: locationId, targetDeviceId: deviceId)
                                },
                                deleteLocation: deleteLocation,
                                logOut: logOut,
                                saveLocations: saveLocations,
                                createLocation: { name in
                                    await createLocationAsync(name: name)
                                },
                            )
                        } else {
                            AllLocationsListView(
                                locations: locations,
                                locationCounts: locationCounts,
                                locationClosedStates: locationClosedStates,
                                deviceCounts: deviceCounts,
                                devices: devices,
                                deviceStatuses: deviceStatuses,
                                onSelectLocation: { location in
                                    viewingLocationId = location.id
                                },
                                onOpenLocationPicker: { showLocationList = true },
                                alertViewModel: alertViewModel
                            )
                        }
                    }
                }
                .id(isServerRunning)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if !isServerRunning {
                            EmptyView()
                        } else if let locationId = viewingLocationId,
                                  let location = locations.first(where: { $0.id == locationId }),
                                  !showLoginScreen {
                            Button(action: { showLocationList = true }) {
                                HStack(spacing: 4) {
                                    Text(location.name)
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else if !showLoginScreen && !locations.isEmpty {
                            Button(action: { showLocationList = true }) {
                                HStack(spacing: 4) {
                                    Text("Locations")
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else if showLoginScreen {
                            AppTitleView(appVersion: appVersion, alertViewModel: alertViewModel)
                        }
                    }
                }
                .onAppear {
                    cleanupLegacyData()
                    loadDevices()
                    loadLocations()
                    cleanupOrphanedDevices()
                    startServerStatusCheck()
                    autoLoginIfNeeded()
                    restoreLastViewedLocation()
                    registerApp()
                    startHeartbeat()
                    alertViewModel.checkForAlert()
                    Task { await migrateLocationsToAutoIds() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DevicePasswordChanged"))) { notification in
                    if let userInfo = notification.userInfo,
                       let deviceId = userInfo["deviceId"] as? String,
                       let newPassword = userInfo["newPassword"] as? String {
                        handlePasswordChanged(deviceId: deviceId, newPassword: newPassword)
                    }
                }
                .onChange(of: locations) { _, newLocations in
                    if let currentId = viewingLocationId,
                       !newLocations.contains(where: { $0.id == currentId }) {
                        viewingLocationId = nil
                    }
                }
                .onChange(of: viewingLocationId) { _, newValue in
                    if let locationId = newValue {
                        UserDefaults.standard.set(locationId, forKey: "cc_lastViewingLocationId")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "cc_lastViewingLocationId")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToOvercrowdingGroup"))) { notification in
                    if let locationId = notification.userInfo?["location_id"] as? String {
                        viewingLocationId = locationId
                    }
                }
                .sheet(isPresented: $showLocationList) {
                    LocationPickerView(
                        locations: $locations,
                        devices: devices,
                        deviceStatuses: deviceStatuses,
                        currentlyViewingLocationId: viewingLocationId,
                        onSave: saveLocations,
                        onDelete: deleteLocation,
                        onNavigateToLocation: { location in
                            viewingLocationId = location.id
                        },
                        onGoToAllLocations: {
                            viewingLocationId = nil
                        },
                        onCreate: { name in
                            await createLocationAsync(name: name)
                        },
                        alertViewModel: alertViewModel
                    )
                }

                if !showLoginScreen && !locations.isEmpty && isServerRunning && networkMonitor.isConnected && viewingLocationId == nil {
                    FloatingButtonsOverlay(
                        showLocationList: $showLocationList
                    )
                }
            }
            AlertOverlay(alertViewModel: alertViewModel)
                .onAppear {
                    alertViewModel.checkForAlert()
                }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .alert("Locations Updated", isPresented: $showReconciliationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(reconciliationMessage)
        }
    }

    // MARK: - Helper Views

    private struct FloatingButtonsOverlay: View {
        @Binding var showLocationList: Bool

        var body: some View {
            VStack {
                Spacer()
                HStack {
                    // Map button (left)
                    NavigationLink(destination: MapContentView()) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "map.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                                .glassEffect(.regular.interactive())
                        } else {
                            Image(systemName: "map.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    .padding(.leading, 20)

                    Spacer()

                    // Location button (right)
                    Button(action: { showLocationList = true }) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                                .glassEffect(.regular.interactive())
                        } else {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private struct ServerStatusView: View {
        let serverStatus: String
        let serverStatusColor: Color
        let networkMonitor = NetworkMonitor.shared
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            if networkMonitor.isConnected && serverStatus == "Server is not running" {
                VStack {
                    Spacer()
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 50))
                        .symbolRenderingMode(.hierarchical)
                        .padding()
                        .foregroundColor(.secondary)
                    Text("We're having trouble connecting you.")
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .bold()
                        .font(.title3)
                        .padding(.horizontal, 40)
                        .padding(5)
                    Text("This could be due to low connection strength, a network issue on our end, or server maintenance.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(.horizontal, 40)
                        .padding(5)
                    Text("Please be patient and try again later.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(10)
                        .padding(.horizontal, 40)
                    Spacer()
                    Text("Visit our website if the issue persists")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(.horizontal, 40)
                    Link("crowdcount.tech/status", destination: URL(string: "https://www.crowdcount.tech/status")!)
                        .font(.body)
                }
            }

            if !networkMonitor.isConnected && !(serverStatusColor == .gray) {
                VStack {
                    Spacer()
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 50))
                        .symbolRenderingMode(.hierarchical)
                        .padding()
                        .foregroundColor(.secondary)
                    (Text("Please go online")
                        .foregroundColor(.primary) +
                     Text(" by turning on and connecting to WiFi or Cellular Data"))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    Spacer()
                }
            }

            if serverStatusColor == .gray {
                VStack {
                    if colorScheme == .dark {
                        Image(.transparentLogo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 125, height: 125)
                    } else {
                        Image("LogoRounded")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .padding(.bottom, 5)
                    }
                    ProgressView()
                }
            }
        }
    }

    class NetworkMonitor: ObservableObject {
        static let shared = NetworkMonitor()
        private var monitor: NWPathMonitor?
        private var queue = DispatchQueue.global(qos: .background)

        @Published private(set) var isConnected: Bool = false

        private init() {
            monitor = NWPathMonitor()
            monitor?.pathUpdateHandler = { [weak self] path in
                DispatchQueue.main.async {
                    self?.isConnected = (path.status == .satisfied)
                }
            }
            monitor?.start(queue: queue)
        }
    }

    private struct NoDevicesView: View {
        @Binding var showLoginScreen: Bool

        var body: some View {
            VStack {
                Text("No devices added. Please add a device.")
                    .foregroundColor(.gray)
                    .padding()
                Button(action: {
                    showLoginScreen = true
                }) {
                    Text("Add Device")
                        .padding()
                        .background(Color.secondary.opacity(0.75))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
        }
    }

    private struct AppTitleView: View {
        let appVersion: String?
        @ObservedObject var alertViewModel: AlertViewModel

        var body: some View {
            Text("CrowdCount")
                .font(.headline)
        }
    }

    // MARK: - Server Status

    func startServerStatusCheck() {
        serverStatusTimer?.invalidate()

        Task {
            await checkServerStatusAsync()
        }

        serverStatusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                await self.checkServerStatusAsync()
            }
        }
    }

    func stopServerStatusCheck() {
        serverStatusTimer?.invalidate()
        serverStatusTimer = nil
    }

    @MainActor
    func checkServerStatusAsync() async {
        let isRunning = await apiService.checkServerStatus()

        if isRunning {
            self.serverStatus = "Server is running"
            self.serverStatusColor = .gray
            self.isServerRunning = true
        } else {
            self.serverStatus = "Server is not running"
            self.serverStatusColor = .red
            self.isServerRunning = false
        }
    }

    // MARK: - Polling

    func startCountPolling() {
        countPollingTimer?.invalidate()
        Task { await refreshAllCounts() }
        countPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in await self.refreshAllCounts() }
        }
    }

    func stopCountPolling() {
        countPollingTimer?.invalidate()
        countPollingTimer = nil
    }

    @MainActor
    func refreshAllCounts() async {
        // Fetch per-device counts (for AllLocationsListView per-device breakdown)
        var newDeviceCounts: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for device in devices {
                group.addTask {
                    let result = try? await self.apiService.fetchCurrentCount(deviceId: device.deviceId, password: device.password)
                    return (device.deviceId, result?.count)
                }
            }
            for await (deviceId, count) in group {
                if let count { newDeviceCounts[deviceId] = count }
            }
        }
        deviceCounts = newDeviceCounts

        // Fetch location-level counts and metadata from server
        for location in locations {
            if let lastChange = lastManualCountChange[location.id],
               Date().timeIntervalSince(lastChange) < 2.0 {
                continue
            }
            guard let auth = locationAuth(for: location) else {
                continue
            }

            // Try fetching this location directly
            do {
                let response = try await apiService.getLocation(
                    locationId: location.id,
                    credentials: auth.credentials,
                    signingDevice: auth.signingDevice
                )
                locationCounts[location.id] = response.currentCount ?? 0
                locationClosedStates[location.id] = response.isClosed
                if let index = locations.firstIndex(where: { $0.id == location.id }) {
                    var changed = false
                    if locations[index].name != response.locationName {
                        locations[index].name = response.locationName
                        changed = true
                    }
                    if locations[index].overcrowdingLimit != response.overcrowdingLimit {
                        locations[index].overcrowdingLimit = response.overcrowdingLimit
                        changed = true
                    }
                    if locations[index].isOnMap != response.isOnMap {
                        locations[index].isOnMap = response.isOnMap
                        changed = true
                    }
                    if locations[index].mapIcon != response.mapIcon {
                        locations[index].mapIcon = response.mapIcon
                        changed = true
                    }
                    if locations[index].mapColor != response.mapColor {
                        locations[index].mapColor = response.mapColor
                        changed = true
                    }
                    if changed { saveLocations() }
                }
            } catch {
                // getLocation failed (e.g. auth requires all devices) — fall through
            }

            // If getLocation failed, keep the previous count (don't aggregate device counts locally)
        }
    }

    func startStatusPolling() {
        statusPollingTimer?.invalidate()
        Task { await refreshAllStatuses() }
        statusPollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in await self.refreshAllStatuses() }
        }
    }

    func stopStatusPolling() {
        statusPollingTimer?.invalidate()
        statusPollingTimer = nil
    }

    @MainActor
    func refreshAllStatuses() async {
        await withTaskGroup(of: (String, String).self) { group in
            for device in devices {
                group.addTask {
                    let status = (try? await self.apiService.checkConnectionStatus(deviceId: device.deviceId, password: device.password)) ?? "offline"
                    return (device.deviceId, status)
                }
            }
            for await (deviceId, status) in group {
                deviceStatuses[deviceId] = status
            }
        }
    }

    // MARK: - Heartbeat

    func startHeartbeat() {
        heartbeatTimer?.invalidate()

        Task {
            await apiService.sendHeartbeat(appId: getAppId())
        }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await self.apiService.sendHeartbeat(appId: self.getAppId())
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Login Flow

    func autoLoginIfNeeded() {
        if !devices.isEmpty {
            showLoginScreen = false
            startCountPolling()
            startStatusPolling()
            prefetchLocationHistory()
            Task {
                // Wait for server to be reachable before checking
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await checkForIncompleteOnMapLocations()
            }
        }
    }

    /// Pre-fetch insights bundle for each location so Count Analytics loads instantly.
    func prefetchLocationHistory() {
        for location in locations {
            let creds = devices.filter { location.deviceIds.contains($0.deviceId) }
                .map { ["device_id": $0.deviceId, "password": $0.password] }
            guard let first = devices.first(where: { location.deviceIds.contains($0.deviceId) }) else { continue }
            let signing = (first.deviceId, first.password)

            Task {
                // Fetch available dates
                if let dates = try? await apiService.fetchLocationAvailableDates(
                    locationId: location.id, credentials: creds, signingDevice: signing
                ) {
                    HistoryPrefetchCache.shared.setDates(locationId: location.id, dates: dates)
                }

                // Compute today's parameters
                let localDate = TZHelper.yyyyMMddLocal(from: Date())
                let utcDates = TZHelper.utcDatesForLocalDay(localDate)
                let currentYear = Calendar.current.component(.year, from: Date())

                // Compute week start (Monday)
                var cal = Calendar.current
                cal.firstWeekday = 2
                let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                let weekStartDate = fmt.string(from: startOfWeek)

                // Fetch insights bundle
                if let bundle = try? await apiService.fetchLocationInsightsBundle(
                    locationId: location.id,
                    date: utcDates.primary,
                    date2: utcDates.secondary,
                    weekDate: weekStartDate,
                    year: currentYear,
                    credentials: creds,
                    signingDevice: signing
                ) {
                    HistoryPrefetchCache.shared.set(locationId: location.id, bundle: bundle)
                }
            }
        }
    }

    func setUser() {
        Task {
            await setUserAsync()
        }
    }

    @MainActor
    func setUserAsync() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        // 1. Validate inputs
        guard !locationName.isEmpty else {
            errorMessage = "Please enter a Location Name"
            return
        }
        guard !userId.isEmpty else {
            errorMessage = "Please enter a Device ID"
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter a Password"
            return
        }

        // 2. Check device not already added locally
        let existingDevice = devices.first(where: { $0.deviceId == userId })
        if let existing = existingDevice {
            // Device exists locally — check if it's actually in a location
            let inAnyLocation = locations.contains(where: { $0.deviceIds.contains(existing.deviceId) })
            if inAnyLocation {
                errorMessage = "Device already added"
                return
            }
            // Device is orphaned (not in any location) — remove stale entry and re-add
            devices.removeAll { $0.deviceId == userId }
            saveDevices()
        }

        do {
            // 3. Check password
            let isPasswordCorrect = try await apiService.checkPassword(deviceId: userId, password: password)

            guard isPasswordCorrect else {
                errorMessage = "Incorrect password"
                return
            }

            // 4. Create Device locally
            let newDevice = Device(id: UUID(), deviceId: userId, password: password)
            devices.append(newDevice)
            saveDevices()

            // 5. Get locations for device → prefer auto-location, fall back to any location
            let serverLocations = try await apiService.getLocationsForDevice(deviceId: userId, password: password)

            if let serverLocation = serverLocations.first(where: { $0.isAuto }) ?? serverLocations.first {
                await completeLogin(autoLocation: serverLocation, device: newDevice)
            } else {
                // Location may not exist yet — retry after delay
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let retryLocations = try await apiService.getLocationsForDevice(deviceId: userId, password: password)
                if let serverLocation = retryLocations.first(where: { $0.isAuto }) ?? retryLocations.first {
                    await completeLogin(autoLocation: serverLocation, device: newDevice)
                } else {
                    errorMessage = "Could not find device location on server"
                    devices.removeAll { $0.deviceId == userId }
                    saveDevices()
                }
            }

        } catch APIError.httpError(404) {
            errorMessage = "Device ID does not exist"
        } catch {
            errorMessage = "Unexpected response from server"
        }
    }

    @MainActor
    private func completeLogin(autoLocation: LocationResponse, device: Device) async {
        let creds = apiService.credentialsBody(from: [device], filterTo: [device.deviceId])
        let signingDevice = (device.deviceId, device.password)

        // 6. Rename auto-location on server (only if not already on the map)
        if autoLocation.isAuto && !autoLocation.isOnMap {
            do {
                try await apiService.updateLocation(
                    locationId: autoLocation.locationId,
                    name: locationName,
                    credentials: creds,
                    signingDevice: signingDevice
                )
            } catch {
                print("Warning: Could not rename auto-location: \(error)")
            }
        }

        // 7. Create or merge into AppLocation locally
        // Check if auto-location already exists locally
        if let existingIndex = locations.firstIndex(where: { $0.id == autoLocation.locationId }) {
            if !locations[existingIndex].deviceIds.contains(device.deviceId) {
                locations[existingIndex].deviceIds.append(device.deviceId)
            }
            saveLocations()
            viewingLocationId = locations[existingIndex].id
        } else {
            // First device, no overlap — create location with just this device
            let newLocation = AppLocation(
                id: autoLocation.locationId,
                name: (autoLocation.isAuto && !autoLocation.isOnMap) ? locationName : autoLocation.locationName,
                deviceIds: [device.deviceId],
                overcrowdingLimit: autoLocation.overcrowdingLimit,
                isOnMap: autoLocation.isOnMap,
                mapIcon: autoLocation.mapIcon,
                mapColor: autoLocation.mapColor
            )
            locations.append(newLocation)
            saveLocations()
            viewingLocationId = newLocation.id
        }

        // 8. Navigate to the location
        showLoginScreen = false

        // 9. Start polling, clear login fields
        startCountPolling()
        startStatusPolling()

        userId = ""
        password = ""
        locationName = ""
        errorMessage = nil

        // Process additional counters from multi-counter login
        if !additionalCounters.isEmpty {
            for counter in additionalCounters {
                guard let currentLocationId = viewingLocationId else { break }
                await addDeviceToLocationAsync(
                    locationId: currentLocationId,
                    newDeviceId: counter.deviceId,
                    password: counter.password,
                    label: counter.deviceId
                )
            }
            additionalCounters = []
        }

        Task { await checkForIncompleteOnMapLocations() }
    }

    // MARK: - Count Modification

    func addToCount(locationId: String, amount: Int) {
        guard locationClosedStates[locationId] != true else { return }
        guard let location = locations.first(where: { $0.id == locationId }),
              let auth = locationAuth(for: location) else { return }

        // Optimistic update + grace period
        locationCounts[locationId, default: 0] += amount
        lastManualCountChange[locationId] = Date()

        Task {
            try? await apiService.locationAddToCount(
                locationId: locationId,
                credentials: auth.credentials,
                signingDevice: auth.signingDevice,
                amount: amount
            )
        }
    }

    func subFromCount(locationId: String, amount: Int) {
        guard locationClosedStates[locationId] != true else { return }
        guard let location = locations.first(where: { $0.id == locationId }),
              let auth = locationAuth(for: location) else { return }

        // Optimistic update + grace period
        locationCounts[locationId, default: 0] = max(0, (locationCounts[locationId] ?? 0) - amount)
        lastManualCountChange[locationId] = Date()

        Task {
            try? await apiService.locationSubFromCount(
                locationId: locationId,
                credentials: auth.credentials,
                signingDevice: auth.signingDevice,
                amount: amount
            )
        }
    }

    // MARK: - Device & Location Management

    /// Build auth credentials for a location from local devices
    private func locationAuth(for location: AppLocation) -> (credentials: [[String: String]], signingDevice: (String, String))? {
        let creds = apiService.credentialsBody(from: devices, filterTo: location.deviceIds)
        guard !creds.isEmpty,
              let firstDevice = devices.first(where: { location.deviceIds.contains($0.deviceId) }) else {
            return nil
        }
        return (creds, (firstDevice.deviceId, firstDevice.password))
    }

    @MainActor
    func addDeviceToLocationAsync(locationId: String, newDeviceId: String, password: String, label: String) async {
        // 1. Check password
        do {
            let isCorrect = try await apiService.checkPassword(deviceId: newDeviceId, password: password)
            guard isCorrect else {
                errorMessage = "Incorrect password for device"
                return
            }
        } catch APIError.httpError(404) {
            errorMessage = "Device ID does not exist"
            return
        } catch {
            errorMessage = "Failed to verify device"
            return
        }

        // 2. Check not already in THIS location
        guard let localIndex = locations.firstIndex(where: { $0.id == locationId }) else {
            errorMessage = "Location not found"
            return
        }
        if locations[localIndex].deviceIds.contains(newDeviceId) {
            errorMessage = "Counter already in this location"
            return
        }

        // 3. Create or update Device locally (reuse existing credentials if already added elsewhere)
        let deviceAlreadyExisted = devices.contains(where: { $0.deviceId == newDeviceId })
        if let existingIdx = devices.firstIndex(where: { $0.deviceId == newDeviceId }) {
            // Update password in case user entered a different one
            devices[existingIdx] = Device(id: devices[existingIdx].id, deviceId: newDeviceId, password: password)
        } else {
            devices.append(Device(id: UUID(), deviceId: newDeviceId, password: password))
        }
        saveDevices()

        // 4. Get the device's server locations to find its real location ID
        let localLocation = locations[localIndex]

        let serverLocations: [LocationResponse]
        do {
            serverLocations = try await apiService.getLocationsForDevice(deviceId: newDeviceId, password: password)
        } catch {
            print("Failed to get server locations for device: \(error)")
            errorMessage = "Failed to connect to server"
            if !deviceAlreadyExisted {
                devices.removeAll { $0.deviceId == newDeviceId }
                saveDevices()
            }
            return
        }

        if localLocation.deviceIds.isEmpty {
            // === FIRST DEVICE: adopt the device's server auto-location ===
            guard let serverLoc = serverLocations.first(where: { $0.isAuto }) ?? serverLocations.first else {
                errorMessage = "Could not find server location for device"
                if !deviceAlreadyExisted {
                    devices.removeAll { $0.deviceId == newDeviceId }
                    saveDevices()
                }
                return
            }

            let serverLocationId = serverLoc.locationId

            // Check if server location already exists locally
            if let existingIndex = locations.firstIndex(where: { $0.id == serverLocationId }) {
                // Server location already tracked — add device to it, remove the empty local one
                if !locations[existingIndex].deviceIds.contains(newDeviceId) {
                    locations[existingIndex].deviceIds.append(newDeviceId)
                }
                locations[existingIndex].isOnMap = serverLoc.isOnMap
                locations[existingIndex].mapIcon = serverLoc.mapIcon
                locations[existingIndex].mapColor = serverLoc.mapColor
                let localIdx = locations.firstIndex(where: { $0.id == locationId })!
                locations.remove(at: localIdx)
                if viewingLocationId == locationId {
                    viewingLocationId = serverLocationId
                }
            } else {
                // Replace local location with server version
                // Use server name for on-map locations; user's chosen name otherwise
                let displayName = serverLoc.isOnMap ? serverLoc.locationName : localLocation.name
                locations[localIndex] = AppLocation(
                    id: serverLocationId,
                    name: displayName,
                    deviceIds: serverLoc.deviceIds.isEmpty ? [newDeviceId] : serverLoc.deviceIds,
                    overcrowdingLimit: serverLoc.overcrowdingLimit,
                    isOnMap: serverLoc.isOnMap,
                    mapIcon: serverLoc.mapIcon,
                    mapColor: serverLoc.mapColor
                )
                if viewingLocationId == locationId {
                    viewingLocationId = serverLocationId
                }
            }

            // Rename the server location to match the user's chosen name (only for non-map locations)
            if !serverLoc.isOnMap {
                let creds = [["device_id": newDeviceId, "password": password]]
                try? await apiService.updateLocation(
                    locationId: serverLocationId,
                    name: localLocation.name,
                    credentials: creds,
                    signingDevice: (newDeviceId, password)
                )
            }
            print("First device added — adopted server location \(serverLocationId)")

        } else {
            // === SUBSEQUENT DEVICE: find or create combined server location ===
            let allDeviceIds = localLocation.deviceIds + [newDeviceId]
            let localDeviceSet = Set(allDeviceIds)

            // Check if a server location already exists with all these devices
            // For on-map locations, only match when device sets are exactly equal
            // (prevents adopting a 3-device map location when user only has 2 devices)
            let sharedServerLoc = serverLocations.first(where: { serverLoc in
                let serverSet = Set(serverLoc.deviceIds)
                if serverLoc.isOnMap {
                    return serverSet == localDeviceSet
                }
                return serverSet.isSuperset(of: localDeviceSet)
            })

            if let sharedLoc = sharedServerLoc {
                // Server already has a location with all these devices — switch to it
                // Unregister from old location's notifications if enabled
                if localLocation.isOvercrowdingNotificationEnabled, sharedLoc.locationId != locationId,
                   let appId = UserDefaults.standard.string(forKey: "appId"),
                   let auth = locationAuth(for: localLocation) {
                    try? await apiService.unregisterLocationOvercrowdingNotification(
                        locationId: locationId, appId: appId, signingDevice: auth.signingDevice
                    )
                }
                locations[localIndex] = AppLocation(
                    id: sharedLoc.locationId,
                    name: sharedLoc.locationName,
                    deviceIds: Array(localDeviceSet),
                    overcrowdingLimit: sharedLoc.overcrowdingLimit,
                    colorName: localLocation.colorName,
                    isOnMap: sharedLoc.isOnMap,
                    mapIcon: sharedLoc.mapIcon,
                    mapColor: sharedLoc.mapColor
                )
                if viewingLocationId == locationId {
                    viewingLocationId = sharedLoc.locationId
                }
                locationCounts[sharedLoc.locationId] = sharedLoc.currentCount ?? 0
                locationClosedStates[sharedLoc.locationId] = sharedLoc.isClosed
                print("Switched to existing server location \(sharedLoc.locationId) (\(sharedLoc.locationName))")
            } else {
                // No shared server location — need to create one on the server
                let allCreds = apiService.credentialsBody(
                    from: devices,
                    filterTo: allDeviceIds
                )
                let deviceLabels = [newDeviceId: label]

                // Always create a new location (server deduplicates by device set hash)
                // Server keeps existing name on dedup; only uses this name for genuinely new locations
                var newLocId: String?
                do {
                    newLocId = try await apiService.createLocation(
                        name: localLocation.name,
                        credentials: allCreds,
                        deviceLabels: deviceLabels,
                        signingDevice: (newDeviceId, password)
                    )
                    print("createLocation succeeded: \(newLocId!)")
                } catch {
                    print("createLocation failed: \(error)")
                    errorMessage = "Failed to create location on server"
                    if !deviceAlreadyExisted {
                        devices.removeAll { $0.deviceId == newDeviceId }
                        saveDevices()
                    }
                    return
                }

                // Update local location with new server ID and device set
                if let newLocId = newLocId {
                    // Fetch the new location's actual data from the server
                    let newCreds = apiService.credentialsBody(from: devices, filterTo: allDeviceIds)
                    var serverName = localLocation.name
                    var serverOvercrowdingLimit: Int? = nil
                    var serverIsOnMap = false
                    var serverCount = 0
                    var serverIsClosed = false
                    var serverMapIcon: String? = nil
                    var serverMapColor: String? = nil
                    if let serverLoc = try? await apiService.getLocation(
                        locationId: newLocId,
                        credentials: newCreds,
                        signingDevice: (newDeviceId, password)
                    ) {
                        serverName = serverLoc.locationName
                        serverOvercrowdingLimit = serverLoc.overcrowdingLimit
                        serverIsOnMap = serverLoc.isOnMap
                        serverCount = serverLoc.currentCount ?? 0
                        serverIsClosed = serverLoc.isClosed
                        serverMapIcon = serverLoc.mapIcon
                        serverMapColor = serverLoc.mapColor
                    }

                    // Unregister from old location's notifications if enabled
                    if localLocation.isOvercrowdingNotificationEnabled, newLocId != locationId,
                       let appId = UserDefaults.standard.string(forKey: "appId"),
                       let auth = locationAuth(for: localLocation) {
                        try? await apiService.unregisterLocationOvercrowdingNotification(
                            locationId: locationId, appId: appId, signingDevice: auth.signingDevice
                        )
                    }
                    locations[localIndex] = AppLocation(
                        id: newLocId,
                        name: serverName,
                        deviceIds: allDeviceIds,
                        overcrowdingLimit: serverOvercrowdingLimit,
                        colorName: localLocation.colorName,
                        isOnMap: serverIsOnMap,
                        mapIcon: serverMapIcon,
                        mapColor: serverMapColor
                    )
                    locationCounts[newLocId] = serverCount
                    locationClosedStates[newLocId] = serverIsClosed
                    if viewingLocationId == locationId {
                        viewingLocationId = newLocId
                    }
                }
            }
        }

        saveLocations()
        errorMessage = nil
    }

    @MainActor
    func removeDeviceFromLocationAsync(locationId: String, targetDeviceId: String) async {
        guard let location = locations.first(where: { $0.id == locationId }) else { return }

        let remainingDeviceIds = location.deviceIds.filter { $0 != targetDeviceId }

        if !remainingDeviceIds.isEmpty {
            // Replace location with remaining devices
            let remainingCreds = apiService.credentialsBody(from: devices, filterTo: remainingDeviceIds)
            guard let firstDevice = devices.first(where: { remainingDeviceIds.contains($0.deviceId) }) else { return }

            // Always create a new location (server deduplicates by device set hash)
            // Server keeps existing name on dedup; only uses this name for genuinely new locations
            var newLocId: String?
            do {
                newLocId = try await apiService.createLocation(
                    name: location.name,
                    credentials: remainingCreds,
                    signingDevice: (firstDevice.deviceId, firstDevice.password)
                )
                print("[Remove] createLocation succeeded: \(newLocId!)")
            } catch {
                print("[Remove] createLocation failed: \(error)")
            }

            if let index = locations.firstIndex(where: { $0.id == locationId }) {
                if let newLocId = newLocId, newLocId != locationId {
                    // Fetch the new location's actual data from the server
                    var serverName = location.name
                    var serverOvercrowdingLimit: Int? = nil
                    var serverIsOnMap = false
                    var serverCount = 0
                    var serverIsClosed = false
                    var serverMapIcon: String? = nil
                    var serverMapColor: String? = nil
                    if let serverLoc = try? await apiService.getLocation(
                        locationId: newLocId,
                        credentials: remainingCreds,
                        signingDevice: (firstDevice.deviceId, firstDevice.password)
                    ) {
                        serverName = serverLoc.locationName
                        serverOvercrowdingLimit = serverLoc.overcrowdingLimit
                        serverIsOnMap = serverLoc.isOnMap
                        serverCount = serverLoc.currentCount ?? 0
                        serverIsClosed = serverLoc.isClosed
                        serverMapIcon = serverLoc.mapIcon
                        serverMapColor = serverLoc.mapColor
                    }

                    // Unregister from old location's notifications if enabled
                    if location.isOvercrowdingNotificationEnabled,
                       let appId = UserDefaults.standard.string(forKey: "appId") {
                        try? await apiService.unregisterLocationOvercrowdingNotification(
                            locationId: locationId, appId: appId,
                            signingDevice: (firstDevice.deviceId, firstDevice.password)
                        )
                    }
                    locations[index] = AppLocation(
                        id: newLocId,
                        name: serverName,
                        deviceIds: remainingDeviceIds,
                        overcrowdingLimit: serverOvercrowdingLimit,
                        colorName: location.colorName,
                        isOnMap: serverIsOnMap,
                        mapIcon: serverMapIcon,
                        mapColor: serverMapColor
                    )
                    locationCounts[newLocId] = serverCount
                    locationClosedStates[newLocId] = serverIsClosed
                    if viewingLocationId == locationId {
                        viewingLocationId = newLocId
                    }
                } else {
                    // Server call failed or returned same ID — still update device list locally
                    locations[index].deviceIds = remainingDeviceIds
                }
            }
        } else {
            // No devices remaining — remove location locally
            locations.removeAll { $0.id == locationId }
        }

        // Also remove the device from the global devices array so it can be re-added later
        devices.removeAll { $0.deviceId == targetDeviceId }
        saveDevices()

        // Clean up empty locations
        locations.removeAll { $0.deviceIds.isEmpty }
        saveLocations()

        if devices.isEmpty && locations.isEmpty {
            showLoginScreen = true
            stopCountPolling()
            stopStatusPolling()
            stopServerStatusCheck()
        }
    }

    func logOut(deviceId: String) {
        // Capture device info before removing
        guard devices.contains(where: { $0.deviceId == deviceId }) else { return }

        // Remove device from all locations (server + local)
        for i in locations.indices {
            if locations[i].deviceIds.contains(deviceId) {
                let location = locations[i]
                let remainingDeviceIds = location.deviceIds.filter { $0 != deviceId }
                if !remainingDeviceIds.isEmpty {
                    let remainingCreds = apiService.credentialsBody(from: devices, filterTo: remainingDeviceIds)
                    if let firstDev = devices.first(where: { remainingDeviceIds.contains($0.deviceId) }) {
                        let signingDevice = (firstDev.deviceId, firstDev.password)
                        let locName = location.name
                        Task {
                            _ = try? await apiService.createLocation(
                                name: locName,
                                credentials: remainingCreds,
                                signingDevice: signingDevice
                            )
                        }
                    }
                }
                locations[i].deviceIds.removeAll { $0 == deviceId }
            }
        }

        // Remove empty locations
        locations.removeAll { $0.deviceIds.isEmpty }

        // Remove device locally
        devices.removeAll { $0.deviceId == deviceId }

        saveDevices()
        saveLocations()

        if devices.isEmpty && locations.isEmpty {
            showLoginScreen = true
            stopCountPolling()
            stopStatusPolling()
            stopServerStatusCheck()
        }
    }

    @MainActor
    func createLocationAsync(name: String) async -> AppLocation? {
        // Create locally only — server location gets created when a device is added
        let newLocation = AppLocation(
            id: UUID().uuidString,
            name: name,
            deviceIds: []
        )
        locations.append(newLocation)
        saveLocations()
        return newLocation
    }

    func deleteLocation(locationId: String) {
        guard let location = locations.first(where: { $0.id == locationId }) else { return }

        // Unregister from overcrowding notifications if enabled
        if location.isOvercrowdingNotificationEnabled {
            if let appId = UserDefaults.standard.string(forKey: "appId"),
               let auth = locationAuth(for: location) {
                Task {
                    try? await apiService.unregisterLocationOvercrowdingNotification(
                        locationId: locationId,
                        appId: appId,
                        signingDevice: auth.signingDevice
                    )
                }
            }
        }

        // Remove the location locally only — do NOT delete on server
        let removedDeviceIds = Set(location.deviceIds)
        locations.removeAll { $0.id == locationId }
        saveLocations()

        // Remove devices that are no longer in any location
        let allLocationDeviceIds = Set(locations.flatMap { $0.deviceIds })
        let orphanedIds = removedDeviceIds.subtracting(allLocationDeviceIds)
        if !orphanedIds.isEmpty {
            devices.removeAll { orphanedIds.contains($0.deviceId) }
            saveDevices()
        }

        if viewingLocationId == locationId {
            viewingLocationId = nil
        }

        if locations.isEmpty {
            showLoginScreen = true
            stopCountPolling()
            stopStatusPolling()
            stopServerStatusCheck()
        }
    }

    // MARK: - Incomplete On-Map Location Check

    @MainActor
    func checkForIncompleteOnMapLocations() async {
        // Only consider devices that are actually in a location (not orphaned)
        let activeDeviceIds = Set(locations.flatMap { $0.deviceIds })
        let activeDevices = devices.filter { activeDeviceIds.contains($0.deviceId) }
        let localDeviceIds = Set(activeDevices.map { $0.deviceId })
        var warningsByLocationId: [String: IncompleteLocationWarning] = [:]

        print("[IncompleteCheck] Starting check with \(activeDevices.count) active devices (of \(devices.count) total): \(localDeviceIds)")

        for device in activeDevices {
            do {
                let serverLocations = try await apiService.getLocationsForDevice(
                    deviceId: device.deviceId, password: device.password
                )
                print("[IncompleteCheck] Device \(device.deviceId) is in \(serverLocations.count) server locations")

                for serverLoc in serverLocations {
                    print("[IncompleteCheck]   Location '\(serverLoc.locationName)' (id=\(serverLoc.locationId), isOnMap=\(serverLoc.isOnMap), isAuto=\(serverLoc.isAuto), devices=\(serverLoc.deviceIds))")

                    guard serverLoc.isOnMap else { continue }

                    // Already recorded this server location
                    if warningsByLocationId[serverLoc.locationId] != nil { continue }

                    let serverDeviceSet = Set(serverLoc.deviceIds)
                    let missingDeviceIds = serverDeviceSet.subtracting(localDeviceIds)

                    print("[IncompleteCheck]   Missing devices: \(missingDeviceIds)")

                    guard !missingDeviceIds.isEmpty else { continue }

                    let userDevicesInLocation = serverDeviceSet.intersection(localDeviceIds)
                    warningsByLocationId[serverLoc.locationId] = IncompleteLocationWarning(
                        id: serverLoc.locationId,
                        serverLocationName: serverLoc.locationName,
                        totalDeviceCount: serverLoc.deviceIds.count,
                        missingDeviceIds: Array(missingDeviceIds),
                        userDeviceIds: Array(userDevicesInLocation)
                    )
                }
            } catch {
                print("[IncompleteCheck] Failed to get locations for device \(device.deviceId): \(error)")
            }
        }

        incompleteLocationWarnings = Array(warningsByLocationId.values)
        print("[IncompleteCheck] Final warnings count: \(incompleteLocationWarnings.count)")
    }

    // MARK: - Persistence

    func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "cc_devices")
        }
    }

    func handlePasswordChanged(deviceId: String, newPassword: String) {
        if let index = devices.firstIndex(where: { $0.deviceId == deviceId }) {
            devices[index] = Device(id: devices[index].id, deviceId: deviceId, password: newPassword)
            saveDevices()
        }
    }

    func saveLocations() {
        if let encoded = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(encoded, forKey: "cc_locations")
        }
    }

    func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: "cc_devices"),
           let decoded = try? JSONDecoder().decode([Device].self, from: data) {
            devices = decoded

            // Bootstrap signing keys on the server for existing devices
            for device in decoded {
                Task {
                    _ = try? await apiService.checkPassword(deviceId: device.deviceId, password: device.password)
                }
            }
        }
    }

    func loadLocations() {
        if let data = UserDefaults.standard.data(forKey: "cc_locations"),
           let decoded = try? JSONDecoder().decode([AppLocation].self, from: data) {
            locations = decoded
        }
    }

    func restoreLastViewedLocation() {
        if let currentId = viewingLocationId,
           !locations.contains(where: { $0.id == currentId }) {
            viewingLocationId = nil
        }
    }

    func cleanupOrphanedDevices() {
        let allLocationDeviceIds = Set(locations.flatMap { $0.deviceIds })
        let before = devices.count
        devices.removeAll { !allLocationDeviceIds.contains($0.deviceId) }
        if devices.count != before {
            print("[Cleanup] Removed \(before - devices.count) orphaned devices")
            saveDevices()
        }
    }

    /// Migrate data from the old User/CounterLocation format to new Device/AppLocation format,
    /// then remove old keys. Safe to call multiple times — skips if already migrated or no old data.
    func cleanupLegacyData() {
        let legacyKeys = ["users", "locations", "userPasswords", "lastViewingLocationId"]
        let hasLegacyData = legacyKeys.contains { UserDefaults.standard.object(forKey: $0) != nil }
        guard hasLegacyData else { return }

        // Only migrate if new data is empty (haven't migrated yet)
        let alreadyMigrated = UserDefaults.standard.data(forKey: "cc_devices") != nil
        if !alreadyMigrated {
            // Decode old users
            struct LegacyUser: Codable, Identifiable {
                let id: UUID
                let userId: String
                var currentCount: Int
                var overcrowdingLimit: Int?
            }
            struct LegacyLocation: Codable, Identifiable {
                let id: UUID
                var name: String
                var deviceIds: [String]
                var overcrowdingLimit: Int?
                var isMapLocation: Bool?
                var mapPrimaryDevice: String?
                var colorName: String?
                var overcrowdingGroupId: String?
                var isOvercrowdingNotificationEnabled: Bool?
            }

            let oldUsers: [LegacyUser] = {
                guard let data = UserDefaults.standard.data(forKey: "users"),
                      let decoded = try? JSONDecoder().decode([LegacyUser].self, from: data) else { return [] }
                return decoded
            }()
            let oldPasswords: [String: String] = {
                guard let data = UserDefaults.standard.data(forKey: "userPasswords"),
                      let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
                return decoded
            }()
            let oldLocations: [LegacyLocation] = {
                guard let data = UserDefaults.standard.data(forKey: "locations"),
                      let decoded = try? JSONDecoder().decode([LegacyLocation].self, from: data) else { return [] }
                return decoded
            }()

            // Convert users → devices (only those with a password)
            var migratedDevices: [Device] = []
            for user in oldUsers {
                guard let pw = oldPasswords[user.id.uuidString] else { continue }
                migratedDevices.append(Device(id: UUID(), deviceId: user.userId, password: pw))
            }

            // Convert locations → AppLocations (use local UUID as temporary id; migrateLocationsToAutoIds fixes later)
            var migratedLocations: [AppLocation] = []
            for loc in oldLocations {
                // Only keep locations that have devices we actually migrated
                let validDeviceIds = loc.deviceIds.filter { did in migratedDevices.contains { $0.deviceId == did } }
                guard !validDeviceIds.isEmpty else { continue }
                migratedLocations.append(AppLocation(
                    id: loc.id.uuidString,
                    name: loc.name,
                    deviceIds: validDeviceIds,
                    overcrowdingLimit: loc.overcrowdingLimit,
                    colorName: loc.colorName,
                    isOvercrowdingNotificationEnabled: loc.isOvercrowdingNotificationEnabled ?? false,
                    isOnMap: loc.isMapLocation ?? false
                ))
            }

            // Handle orphaned users (have a password but aren't in any location) — create a location for each
            let allLocationDeviceIds = Set(migratedLocations.flatMap { $0.deviceIds })
            for device in migratedDevices where !allLocationDeviceIds.contains(device.deviceId) {
                migratedLocations.append(AppLocation(
                    id: UUID().uuidString,
                    name: device.deviceId,
                    deviceIds: [device.deviceId]
                ))
            }

            if !migratedDevices.isEmpty {
                devices = migratedDevices
                saveDevices()
                locations = migratedLocations
                saveLocations()
                print("[Migration] Migrated \(migratedDevices.count) devices and \(migratedLocations.count) locations from legacy format")
            }
        }

        // Remove old keys
        for key in legacyKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Migration

    /// Migrate locations to use server auto-location IDs, and ensure multi-device locations
    /// exist on the server. Handles both:
    /// - Locations stored with a map/local UUID that need the correct server ID
    /// - Multi-device locations from legacy migration that need devices added on the server
    @MainActor
    func migrateLocationsToAutoIds() async {
        let migrationKey = "cc_migrated_to_auto_location_ids"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        guard !locations.isEmpty, !devices.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        var changed = false
        for (index, location) in locations.enumerated() {
            guard let firstDeviceId = location.deviceIds.first,
                  let device = devices.first(where: { $0.deviceId == firstDeviceId }) else { continue }

            // Ask server for this device's locations
            guard let serverLocations = try? await apiService.getLocationsForDevice(
                deviceId: device.deviceId, password: device.password
            ) else { continue }

            // For multi-device locations, check if a server location already has all our devices
            let localDeviceSet = Set(location.deviceIds)
            let matchingServerLoc = serverLocations.first(where: { Set($0.deviceIds).isSuperset(of: localDeviceSet) })

            if let match = matchingServerLoc {
                // Server already has a location with all our devices — use its ID
                if location.id != match.locationId {
                    let migrated = AppLocation(
                        id: match.locationId,
                        name: location.name,
                        deviceIds: location.deviceIds,
                        overcrowdingLimit: match.overcrowdingLimit,
                        colorName: location.colorName,
                        isOnMap: match.isOnMap,
                        mapIcon: match.mapIcon,
                        mapColor: match.mapColor
                    )
                    locations[index] = migrated
                    if viewingLocationId == location.id {
                        viewingLocationId = match.locationId
                    }
                    changed = true
                    print("[Migration] Location '\(location.name)' matched existing server location \(match.locationId)")
                }
            } else if let autoLoc = serverLocations.first(where: { $0.isAuto }) {
                // No server location has all devices — use the auto-location and add missing devices
                let serverLocationId = autoLoc.locationId

                if location.id != serverLocationId {
                    let migrated = AppLocation(
                        id: serverLocationId,
                        name: location.name,
                        deviceIds: location.deviceIds,
                        overcrowdingLimit: autoLoc.overcrowdingLimit,
                        colorName: location.colorName,
                        isOnMap: autoLoc.isOnMap,
                        mapIcon: autoLoc.mapIcon,
                        mapColor: autoLoc.mapColor
                    )
                    locations[index] = migrated
                    if viewingLocationId == location.id {
                        viewingLocationId = serverLocationId
                    }
                    changed = true
                    print("[Migration] Location '\(location.name)' migrated to auto-location \(serverLocationId)")
                }

                // Replace location with full device set
                if location.deviceIds.count > 1 {
                    let allCreds = apiService.credentialsBody(from: devices, filterTo: location.deviceIds)
                    var newLocId: String?
                    newLocId = try? await apiService.createLocation(
                        name: location.name,
                        credentials: allCreds,
                        signingDevice: (device.deviceId, device.password)
                    )
                    if let id = newLocId { print("[Migration] createLocation → \(id)") }
                    if let newLocId = newLocId, newLocId != serverLocationId {
                        // Fetch the new location's actual data from the server
                        var serverName = location.name
                        var serverOvercrowdingLimit: Int? = nil
                        var serverIsOnMap = false
                        var srvMapIcon: String? = nil
                        var srvMapColor: String? = nil
                        if let serverLoc = try? await apiService.getLocation(
                            locationId: newLocId,
                            credentials: allCreds,
                            signingDevice: (device.deviceId, device.password)
                        ) {
                            serverName = serverLoc.locationName
                            serverOvercrowdingLimit = serverLoc.overcrowdingLimit
                            serverIsOnMap = serverLoc.isOnMap
                            srvMapIcon = serverLoc.mapIcon
                            srvMapColor = serverLoc.mapColor
                        }
                        locations[index] = AppLocation(
                            id: newLocId,
                            name: serverName,
                            deviceIds: location.deviceIds,
                            overcrowdingLimit: serverOvercrowdingLimit,
                            colorName: location.colorName,
                            isOnMap: serverIsOnMap,
                            mapIcon: srvMapIcon,
                            mapColor: srvMapColor
                        )
                        if viewingLocationId == serverLocationId {
                            viewingLocationId = newLocId
                        }
                        changed = true
                    }
                }
            }
        }

        if changed {
            saveLocations()
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - App Registration

    func registerApp() {
        Task {
            await apiService.registerApp(appId: getAppId())
            // Report version for each managed device
            for device in devices {
                await apiService.reportAppVersion(deviceId: device.deviceId, password: device.password)
            }
        }
    }

    func getAppId() -> String {
        if let appId = UserDefaults.standard.string(forKey: "appId") {
            return appId
        } else {
            let appId = UUID().uuidString
            UserDefaults.standard.set(appId, forKey: "appId")
            return appId
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
