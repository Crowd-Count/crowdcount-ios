import SwiftUI
import CoreBluetooth
import Network
import UIKit

struct User: Identifiable, Codable {
    let id: UUID
    let userId: String
    var currentCount: Int
    var overcrowdingLimit: Int?
}

struct ContentView: View {
    @State private var users: [User] = []
    @State private var currentUserIndex: Int = 0
    @State private var totalCount: Int = 0
    @State private var totalOvercrowdingCount: Int = 0
    @State private var showSettings: Bool = false
    @State private var selectedUserForSettings: User?
    @State private var userId: String = ""
    @State private var password: String = ""
    @State private var currentCount: String = ""
    @State private var newCount: String = ""
    @State private var errorMessage: String?
    @State private var showNewCountField: Bool = false
    @State private var serverStatus: String = "Loading..."
    @State private var serverStatusColor: Color = .gray
    @State private var isServerRunning: Bool = false
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""
    @State private var availableNetworks: [String] = []
    @ObservedObject private var bluetoothManager: BluetoothManager
    @State private var updateFrequencies: [UUID: Double] = [:]
    @State private var liveCountUpdateTimers: [UUID: Timer] = [:]
    @State private var deviceStatusCheckTimers: [UUID: Timer] = [:]
    @State private var overcrowdingUpdateTimer: Timer?
    @State private var serverStatusTimer: Timer?
    @State private var heartbeatTimer: Timer?
    @State private var deviceStatuses: [UUID: String] = [:]

    // API Service for optimized networking
    private let apiService = APIService.shared

    // MARK: - Location-Centric Model State
    @State private var locations: [CrowdCountLocation] = []
    @State private var counterPasswords: [String: String] = [:]
    private let migrationManager = MigrationManager.shared
    @State private var locationUpdateTimer: Timer?
    @State private var isBluetoothSetupRequired: [UUID: Bool] = [:]
    @State private var showLoginScreen: Bool = true
    @State private var path = NavigationPath()
    @State private var isAddingCounter: Bool = false
    @State private var userPasswords: [UUID: String] = [:] // Store passwords per user
    @StateObject private var alertViewModel = AlertViewModel()
    
    @EnvironmentObject var appSettings: AppSettings
    
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let serverURL = AppSettings.apiBaseURL
    
    let networkMonitor = NetworkMonitor.shared

    init() {
        _bluetoothManager = ObservedObject(wrappedValue: BluetoothManager())
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Add colored edges with adaptive color
                BlurredEdgesViewRepresentable(
                    edgeColor: .label,
                    edgeThickness: 10
                ).edgesIgnoringSafeArea(.all)
                
                // Overlay the blur effect with adaptive blur style
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
                            errorMessage: $errorMessage,
                            setUser: setUser,
                            serverStatus: serverStatus,
                            serverStatusColor: serverStatusColor
                        )
                    } else {
                        // Conditional rendering based on feature flag
                        if appSettings.useLocationCentricUI {
                            // New location-centric UI
                            if locations.isEmpty {
                                NoLocationsView(onAddDevice: { showLoginScreen = true })
                            } else {
                                LocationsTabView(
                                    locations: $locations,
                                    counterPasswords: $counterPasswords,
                                    serverURL: serverURL,
                                    onAddDevice: { showLoginScreen = true },
                                    onModifyCount: { counter in
                                        // Handle modify count for counter
                                        handleModifyCount(for: counter)
                                    },
                                    onViewHistory: { counter in
                                        // Handle view history for counter
                                        handleViewHistory(for: counter)
                                    },
                                    onViewAggregatedHistory: { location in
                                        // Handle view aggregated history for location
                                        handleViewAggregatedHistory(for: location)
                                    }
                                )
                            }
                        } else {
                            // Legacy counter-centric UI
                            if users.isEmpty {
                                NoDevicesView(showLoginScreen: $showLoginScreen)
                            } else {
                                UsersTabView(
                                    users: $users,
                                    currentUserIndex: $currentUserIndex,
                                    totalCount: $totalCount,
                                    totalOvercrowdingCount: $totalOvercrowdingCount,
                                    userPasswords: $userPasswords,
                                    showNewCountField: $showNewCountField,
                                    newCount: $newCount,
                                    setCurrentCount: setCurrentCount,
                                    isBluetoothSetupRequired: $isBluetoothSetupRequired,
                                    bluetoothManager: bluetoothManager,
                                    wifiSSID: $wifiSSID,
                                    wifiPassword: $wifiPassword,
                                    sendWiFiCredentials: sendWiFiCredentials,
                                    deviceStatuses: $deviceStatuses,
                                    serverURL: serverURL,
                                    startDeviceStatusCheck: startDeviceStatusCheck,
                                    updateFrequencies: $updateFrequencies,
                                    showSettings: $showSettings,
                                    selectedUserForSettings: $selectedUserForSettings,
                                    logOut: logOut,
                                    startLiveCountUpdate: startLiveCountUpdate
                                )
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        AppTitleView(appVersion: appVersion, alertViewModel: alertViewModel)
                    }
                }
                .onAppear {
                    loadUsers()
                    startServerStatusCheck()
                    autoLoginIfNeeded()
                    registerApp()
                    startHeartbeat()  // Start sending heartbeats
                    alertViewModel.checkForAlert()

                    // Location-centric UI initialization
                    if appSettings.useLocationCentricUI {
                        Task {
                            await loadLocations()
                        }
                    }
                }
                .onChange(of: updateFrequencies) {
                    DispatchQueue.main.async {
                        startLiveCountUpdate()
                    }
                }
                .onChange(of: locations) { _, newValue in
                    // Auto-save locations whenever they change
                    migrationManager.saveLocations(newValue)
                }
                .navigationDestination(for: String.self) { value in
                    if value == "BluetoothSetupView" {
                        BluetoothSetupView(
                            wifiSSID: $wifiSSID,
                            wifiPassword: $wifiPassword,
                            bluetoothManager: bluetoothManager,
                            sendWiFiCredentials: sendWiFiCredentials
                        )
                    }
                }
                .sheet(item: $selectedUserForSettings) { user in
                    SettingsView(
                        showSettings: $showSettings,
                        user: user,
                        updateFrequencies: $updateFrequencies,
                        userPasswords: $userPasswords,
                        logOut: logOut,
                        serverURL: serverURL
                    )
                }
                if !showLoginScreen && isServerRunning && networkMonitor.isConnected {
                    MapButtonOverlay()
                }
            }
            AlertOverlay(alertViewModel: alertViewModel)
            .onAppear {
                alertViewModel.checkForAlert()
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    private struct MapButtonOverlay: View {
        var body: some View {
            VStack {
                Spacer()
                HStack {
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
                                .glassEffect()
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
                        .padding(.horizontal,40)
                        .padding(5)
                    Text("This could be due to low connection strength, a network issue on our end, or server maintenance.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(.horizontal,40)
                        .padding(5)
                    Text("Please be patient and try again later.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(10)
                        .padding(.horizontal,40)
                    Spacer()
                    Text("Visit our website if the issue persists")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
//                        .padding()
                        .padding(.horizontal,40)
                    Text("\(Text("[crowdcount.tech/status](https://www.crowdcount.tech/status)"))")
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
                    if (colorScheme == .dark) {
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
        
    class NetworkMonitor {
        static let shared = NetworkMonitor()
        private var monitor: NWPathMonitor?
        private var queue = DispatchQueue.global(qos: .background)
        
        private(set) var isConnected: Bool = false
        
        private init() {
            monitor = NWPathMonitor()
            monitor?.pathUpdateHandler = { [weak self] path in
                self?.isConnected = (path.status == .satisfied)
                print(self?.isConnected == true ? "Connected" : "Not Connected")
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

    private struct UsersTabView: View {
        @Binding var users: [User]
        @Binding var currentUserIndex: Int
        @Binding var totalCount: Int
        @Binding var totalOvercrowdingCount: Int
        @Binding var userPasswords: [UUID: String]
        @Binding var showNewCountField: Bool
        @Binding var newCount: String
        let setCurrentCount: (User, String) -> Void
        @Binding var isBluetoothSetupRequired: [UUID: Bool]
        @ObservedObject var bluetoothManager: BluetoothManager
        @Binding var wifiSSID: String
        @Binding var wifiPassword: String
        let sendWiFiCredentials: () -> Void
        @Binding var deviceStatuses: [UUID: String]
        let serverURL: String
        let startDeviceStatusCheck: (User) -> Void
        @Binding var updateFrequencies: [UUID: Double]
        @Binding var showSettings: Bool
        @Binding var selectedUserForSettings: User?
        let logOut: (UUID) -> Void
        let startLiveCountUpdate: () -> Void

        var body: some View {
            TabView(selection: $currentUserIndex) {
                // Total Count view (if multiple users)
                if users.count > 1 {
                    TotalCountView(totalCount: totalCount, totalOvercrowdingCount: totalOvercrowdingCount, users: users, userPasswords: $userPasswords)
                        .tag(0)
                }

                // Individual user views
                ForEach(users.indices, id: \.self) { index in
                    userView(for: index)
                        .tag(users.count > 1 ? index + 1 : index)
                }

                // Add Device page (rightmost)
                AddUserPage(
                    users: $users,
                    totalCount: $totalCount,
                    userPasswords: $userPasswords,
                    serverURL: serverURL,
                    startDeviceStatusCheck: startDeviceStatusCheck,
                    startLiveCountUpdate: startLiveCountUpdate
                )
                .tag(users.count + (users.count > 1 ? 1 : 0))
            }
            .tabViewStyle(PageTabViewStyle())
            .onAppear {
                setupPageControlAppearance()
            }
        }
        
        private func setupPageControlAppearance() {
            UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.label // Active page indicator color
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.5) // Inactive page indicator color
        }

        @ViewBuilder
        private func userView(for index: Int) -> some View {
            UserView(
                user: $users[index],
                users: $users,
                serverURL: serverURL,
                userPasswords: $userPasswords,
                setCurrentCount: setCurrentCount,
                isBluetoothSetupRequired: Binding(
                    get: { isBluetoothSetupRequired[users[index].id] ?? false },
                    set: { isBluetoothSetupRequired[users[index].id] = $0 }
                ),
                bluetoothManager: bluetoothManager,
                sendWiFiCredentials: sendWiFiCredentials,
                deviceStatusMessage: Binding(
                    get: { deviceStatuses[users[index].id] ?? "" },
                    set: { deviceStatuses[users[index].id] = $0 }
                ),
                showSettings: $showSettings,
                updateFrequencies: $updateFrequencies,
                logOut: logOut,
                showSettingsForUser: {
                    selectedUserForSettings = users[index]
                    showSettings = true
                }
            )
        }
    }

    private struct AppTitleView: View {
        let appVersion: String?
        @ObservedObject var alertViewModel: AlertViewModel

        var body: some View {
            Button(action: {
                if alertViewModel.alertExists {
                    alertViewModel.showAlert.toggle()
                }
            }) {
                VStack {
                    Text("CrowdCount")
                        .font(.headline)
                        .overlay(alignment: .topTrailing) {
                            if alertViewModel.alertExists {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 18, y: 5.5)
                            }
                        }
                    Text("CrowdCount App v\(appVersion ?? "ersion undefined")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(NoOpacityChangeButtonStyle())
            .contentShape(Rectangle()) // Ensure the whole area is tappable
            .disabled(!alertViewModel.alertExists) // Disable button if there's no alert
        }
    }

    struct NoOpacityChangeButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(1.0) // Ensure the opacity does not change
        }
    }

    func startServerStatusCheck() {
        // Invalidate existing timer if any
        serverStatusTimer?.invalidate()

        // Check immediately
        Task {
            await checkServerStatusAsync()
        }

        // Then check every 3 seconds
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

    func startLiveCountUpdate() {
        for timer in liveCountUpdateTimers.values {
            timer.invalidate()
        }
        liveCountUpdateTimers.removeAll()

        for user in users {
            let frequency = updateFrequencies[user.id, default: 1.0]
            liveCountUpdateTimers[user.id] = Timer.scheduledTimer(withTimeInterval: frequency, repeats: true) { _ in
                fetchCurrentCount(for: user.id)
            }
        }

        // Start overcrowding update timer (every 5 seconds)
        startOvercrowdingUpdateTimer()
    }

    func startOvercrowdingUpdateTimer() {
        overcrowdingUpdateTimer?.invalidate()

        // Fetch immediately, then every 5 seconds
        refreshAllOvercrowdingLimits()

        overcrowdingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.refreshAllOvercrowdingLimits()
        }
    }

    func stopOvercrowdingUpdateTimer() {
        overcrowdingUpdateTimer?.invalidate()
        overcrowdingUpdateTimer = nil
    }

    func checkServerStatus() {
        Task {
            await checkServerStatusAsync()
        }
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

    func startHeartbeat() {
        // Invalidate existing timer if any
        heartbeatTimer?.invalidate()

        // Send immediately
        Task {
            await apiService.sendHeartbeat(appId: getAppId())
        }

        // Then send every 30 seconds
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

    func sendWiFiCredentials() {
        // This function is no longer used - BluetoothSetupView handles provisioning internally
        // Kept for backward compatibility with view signatures
    }

    func autoLoginIfNeeded() {
        if !userId.isEmpty && !password.isEmpty {
            setUser()
        } else {
            checkStoredUsers()
        }
    }

    func fetchCurrentCount(for userId: UUID) {
        Task {
            await fetchCurrentCountAsync(for: userId)
        }
    }

    @MainActor
    func fetchCurrentCountAsync(for userId: UUID) async {
        guard let userIndex = users.firstIndex(where: { $0.id == userId }) else {
            print("User not found for ID: \(userId)")
            return
        }

        let user = users[userIndex]

        do {
            let result = try await apiService.fetchCurrentCount(deviceId: user.userId)

            // Always update UI with the fetched count to ensure consistency
            if let updatedIndex = self.users.firstIndex(where: { $0.id == userId }) {
                if self.users[updatedIndex].currentCount != result.count {
                    self.users[updatedIndex].currentCount = result.count
                    self.calculateTotalCount()
                }
            }
        } catch {
            print("Error fetching current count for user: \(user.userId): \(error)")
        }
    }

    /// Fetch all current counts in parallel - more efficient for multiple users
    @MainActor
    func fetchAllCurrentCounts() async {
        let userList = users.map { (id: $0.id, deviceId: $0.userId) }
        let results = await apiService.fetchAllCurrentCounts(users: userList)

        var changed = false
        for (id, count) in results {
            if let index = users.firstIndex(where: { $0.id == id }) {
                if users[index].currentCount != count {
                    users[index].currentCount = count
                    changed = true
                }
            }
        }

        if changed {
            calculateTotalCount()
        }
    }

    func setCurrentCount(user: User, count: String) {
        Task {
            await setCurrentCountAsync(user: user, count: count)
        }
    }

    @MainActor
    func setCurrentCountAsync(user: User, count: String) async {
        print("setCurrentCount called for user: \(user.userId) with count: \(count)")

        guard !count.isEmpty, let newCount = Int(count) else {
            errorMessage = "Please enter a valid count"
            print("Error: Invalid count")
            return
        }

        guard let password = userPasswords[user.id] else {
            errorMessage = "Password not found for user"
            print("Error: Password not found for user \(user.userId)")
            return
        }

        do {
            try await apiService.setCurrentCount(deviceId: user.userId, password: password, newCount: newCount)
            self.errorMessage = nil
            self.showNewCountField = false
            print("Successfully updated count for user: \(user.userId)")

            // Fetch updated count - always makes a fresh request now
            await fetchCurrentCountAsync(for: user.id)
        } catch {
            self.errorMessage = "Failed to update count"
            print("Failed to update count: \(error)")
        }
    }

    func setUser() {
        Task {
            await setUserAsync()
        }
    }

    @MainActor
    func setUserAsync() async {
        // Prevent multiple concurrent calls
        guard !isAddingCounter else { return }
        isAddingCounter = true
        defer { isAddingCounter = false }

        guard !userId.isEmpty else {
            errorMessage = "Please enter a Device ID"
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Please enter a Password"
            return
        }

        do {
            let isPasswordCorrect = try await apiService.checkPassword(deviceId: userId, password: password)

            if isPasswordCorrect {
                self.errorMessage = nil

                // Check if device already added (only check relevant model based on mode)
                let alreadyAdded: Bool
                if appSettings.useLocationCentricUI {
                    // In location-centric mode, only check locations
                    alreadyAdded = self.locations.flatMap { $0.counters }.contains(where: { $0.deviceId == self.userId })
                } else {
                    // In legacy mode, only check users
                    alreadyAdded = self.users.contains(where: { $0.userId == self.userId })
                }

                if alreadyAdded {
                    self.errorMessage = "Device already added"
                } else {
                    // Capture values before async operations
                    let deviceId = self.userId
                    let devicePassword = self.password

                    if appSettings.useLocationCentricUI {
                        // Location-centric mode: add to locations only
                        if let newLocation = await migrationManager.addCounter(deviceId: deviceId, password: devicePassword) {
                            if let existingIndex = self.locations.firstIndex(where: { $0.id == newLocation.id }) {
                                self.locations[existingIndex] = newLocation
                            } else {
                                self.locations.append(newLocation)
                            }
                            self.counterPasswords[deviceId] = devicePassword
                            self.showLoginScreen = false
                            startLocationUpdates()
                        } else {
                            self.errorMessage = "Failed to add counter. Please try again."
                        }
                    } else {
                        // Legacy mode: add to users array
                        let newUser = User(id: UUID(), userId: deviceId, currentCount: 0)
                        self.users.append(newUser)
                        self.userPasswords[newUser.id] = devicePassword
                        self.calculateTotalCount()
                        self.calculateTotalOvercrowdingCount()
                        self.showLoginScreen = false
                        self.startDeviceStatusCheck(for: newUser)
                        await self.fetchCurrentCountAsync(for: newUser.id)
                        self.startLiveCountUpdate()
                        saveUsers()
                    }
                }
            } else {
                self.errorMessage = "Incorrect password"
            }
        } catch APIError.httpError(404) {
            self.errorMessage = "Device ID does not exist"
        } catch {
            self.errorMessage = "Unexpected response from server"
        }
    }

    func checkStoredUsers() {
        if let savedUsers = UserDefaults.standard.object(forKey: "users") as? Data {
            let decoder = JSONDecoder()
            if let decodedUsers = try? decoder.decode([User].self, from: savedUsers) {
                users = decodedUsers
                for user in users {
                    startDeviceStatusCheck(for: user)
                }
                calculateTotalCount()
                calculateTotalOvercrowdingCount()
                DispatchQueue.main.async {
                    startLiveCountUpdate()
                }
            }
        }
        if let savedPasswords = UserDefaults.standard.object(forKey: "userPasswords") as? Data {
            let decoder = JSONDecoder()
            if let decodedPasswords = try? decoder.decode([UUID: String].self, from: savedPasswords) {
                userPasswords = decodedPasswords
            }
        }
        // Only set showLoginScreen based on users in legacy mode
        // In location-centric mode, loadLocations() handles this
        if !appSettings.useLocationCentricUI {
            if users.isEmpty {
                showLoginScreen = true
            } else {
                showLoginScreen = false
            }
        }
    }

    func calculateTotalCount() {
        totalCount = users.reduce(0) { $0 + $1.currentCount }
    }

    func fetchOvercrowdingLimit(for userId: UUID) {
        Task {
            await fetchOvercrowdingLimitAsync(for: userId)
        }
    }

    @MainActor
    func fetchOvercrowdingLimitAsync(for userId: UUID) async {
        guard let userIndex = users.firstIndex(where: { $0.id == userId }) else {
            print("User not found for ID: \(userId)")
            return
        }

        let user = users[userIndex]

        do {
            let result = try await apiService.fetchOvercrowdingLimit(deviceId: user.userId)

            // Only update UI if the value actually changed
            if result.changed {
                if let updatedIndex = self.users.firstIndex(where: { $0.id == userId }) {
                    self.users[updatedIndex].overcrowdingLimit = result.limit
                    self.calculateTotalOvercrowdingCount()
                }
            }
        } catch {
            print("Error fetching overcrowding for user: \(user.userId): \(error)")
        }
    }

    func calculateTotalOvercrowdingCount() {
        // Calculate from stored values - no API calls needed
        totalOvercrowdingCount = users.compactMap { $0.overcrowdingLimit }.reduce(0, +)
    }

    func refreshAllOvercrowdingLimits() {
        Task {
            await refreshAllOvercrowdingLimitsAsync()
        }
    }

    /// Fetch all overcrowding limits in parallel - more efficient for multiple users
    @MainActor
    func refreshAllOvercrowdingLimitsAsync() async {
        let userList = users.map { (id: $0.id, deviceId: $0.userId) }
        let results = await apiService.fetchAllOvercrowdingLimits(users: userList)

        var changed = false
        for (id, limit) in results {
            if let index = users.firstIndex(where: { $0.id == id }) {
                if users[index].overcrowdingLimit != limit {
                    users[index].overcrowdingLimit = limit
                    changed = true
                }
            }
        }

        if changed {
            calculateTotalOvercrowdingCount()
        }
    }

    func logOut(userId: UUID) {
        print("Before logout - currentUserIndex: \(currentUserIndex), users.count: \(users.count)")
        
        if let index = self.users.firstIndex(where: { $0.id == userId }) {
            print("Logging out user with ID: \(userId) at index: \(index)")
            
            self.liveCountUpdateTimers[userId]?.invalidate()
            self.liveCountUpdateTimers.removeValue(forKey: userId)
            
            self.deviceStatusCheckTimers[userId]?.invalidate()
            self.deviceStatusCheckTimers.removeValue(forKey: userId)
            
            self.users.remove(at: index)
            
            self.saveUsers()
            
            if self.users.isEmpty {
                self.showLoginScreen = true
                self.currentUserIndex = 0
                self.stopOvercrowdingUpdateTimer()
            } else {
                self.currentUserIndex = min(index, self.users.count - 1)
            }
            
            self.userId = ""
            self.password = ""
            UserDefaults.standard.removeObject(forKey: "userId")
            UserDefaults.standard.removeObject(forKey: "password")
            
            self.userPasswords.removeValue(forKey: userId)
            
            self.updateFrequencies.removeValue(forKey: userId)

            self.calculateTotalCount()
            self.calculateTotalOvercrowdingCount()

            print("After logout - currentUserIndex: \(self.currentUserIndex), users.count: \(self.users.count)")
        } else {
            print("Error: User with ID \(userId) not found")
        }
    }

    func saveUsers() {
        if let encoded = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encoded, forKey: "users")
        }
        if let encodedPasswords = try? JSONEncoder().encode(userPasswords) {
            UserDefaults.standard.set(encodedPasswords, forKey: "userPasswords")
        }
    }

    func loadUsers() {
        if let savedUsers = UserDefaults.standard.object(forKey: "users") as? Data {
            let decoder = JSONDecoder()
            if let decodedUsers = try? decoder.decode([User].self, from: savedUsers) {
                users = decodedUsers
                for user in users {
                    startDeviceStatusCheck(for: user)
                }
                calculateTotalCount()
                calculateTotalOvercrowdingCount()
                DispatchQueue.main.async {
                    startLiveCountUpdate()
                }
            }
        }
        if let savedPasswords = UserDefaults.standard.object(forKey: "userPasswords") as? Data {
            let decoder = JSONDecoder()
            if let decodedPasswords = try? decoder.decode([UUID: String].self, from: savedPasswords) {
                userPasswords = decodedPasswords
            }
        }
    }

    // MARK: - Location-Centric UI Methods

    /// Load locations from migration manager (performs migration if needed)
    @MainActor
    func loadLocations() async {
        locations = await migrationManager.performMigrationIfNeeded()
        counterPasswords = migrationManager.loadCounterPasswords()

        // Start periodic updates if we have locations
        if !locations.isEmpty {
            showLoginScreen = false
            startLocationUpdates()
        }
    }

    /// Start periodic location data updates
    func startLocationUpdates() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                await self.refreshLocationData()
            }
        }
    }

    /// Refresh location data from server
    @MainActor
    func refreshLocationData() async {
        guard !locations.isEmpty else { return }

        do {
            let serverData = try await apiService.fetchAllLocationData()

            // Update existing locations with fresh data from server
            for i in locations.indices {
                if let serverLocation = serverData.first(where: { $0.location_device == locations[i].id }) {
                    // Update aggregated data
                    locations[i].comparison = serverLocation.location_comparison

                    // Update counter data if breakdown available
                    if let breakdown = serverLocation.device_breakdown, !breakdown.isEmpty {
                        for j in locations[i].counters.indices {
                            if let deviceData = breakdown.first(where: { $0.device_id == locations[i].counters[j].deviceId }) {
                                locations[i].counters[j].currentCount = deviceData.count
                                locations[i].counters[j].overcrowdingLimit = deviceData.overcrowding.intValue
                            }
                        }
                    } else {
                        // Single counter location - update from aggregated count
                        if locations[i].counters.count == 1 {
                            locations[i].counters[0].currentCount = serverLocation.location_current_count
                            locations[i].counters[0].overcrowdingLimit = serverLocation.location_overcrowding_count.intValue
                        }
                    }
                }
            }

            // Save updated locations
            migrationManager.saveLocations(locations)
        } catch {
            // Silently handle error - will retry on next interval
        }
    }

    /// Handle modify count action for a counter (placeholder - integrate with existing modify count flow)
    func handleModifyCount(for counter: Counter) {
        // Find the legacy user if exists, or create temporary user for the modify count sheet
        if let password = counterPasswords[counter.deviceId] {
            // Check if we already have a User for this device
            if let existingUser = users.first(where: { $0.userId == counter.deviceId }) {
                // Use existing user
                userPasswords[existingUser.id] = password
                selectedUserForSettings = existingUser
            } else {
                // Create a temporary User for the existing modify count flow
                let tempUser = User(id: UUID(), userId: counter.deviceId, currentCount: counter.currentCount, overcrowdingLimit: counter.overcrowdingLimit)
                userPasswords[tempUser.id] = password
                users.append(tempUser)
                selectedUserForSettings = tempUser
            }
            showSettings = true
        }
    }

    /// Handle view history action for a counter (placeholder - integrate with existing history flow)
    func handleViewHistory(for counter: Counter) {
        // Navigate to HistoricView for this counter
        // This would need integration with the existing navigation flow
    }

    /// Handle view aggregated history for a location (placeholder - integrate with aggregated history view)
    func handleViewAggregatedHistory(for location: CrowdCountLocation) {
        // Navigate to AggregatedHistoricView for all counters in this location
        // This would need integration with the existing navigation flow
    }

    func startDeviceStatusCheck(for user: User) {
        deviceStatusCheckTimers[user.id]?.invalidate()
        deviceStatusCheckTimers[user.id] = Timer.scheduledTimer(withTimeInterval: updateFrequencies[user.id, default: 1.0], repeats: true) { _ in
            self.checkDeviceStatus(for: user)
        }
    }

    func checkDeviceStatus(for user: User) {
        Task {
            await checkDeviceStatusAsync(for: user)
        }
    }

    @MainActor
    func checkDeviceStatusAsync(for user: User) async {
        do {
            let status = try await apiService.checkConnectionStatus(deviceId: user.userId)

            if status == "online" {
                self.deviceStatuses[user.id] = "Device is connected"
                self.isBluetoothSetupRequired[user.id] = false
            } else {
                self.deviceStatuses[user.id] = "Device cannot connect to the server"
                self.isBluetoothSetupRequired[user.id] = true
            }
        } catch {
            self.deviceStatuses[user.id] = "Device cannot connect to the server"
            self.isBluetoothSetupRequired[user.id] = true
        }
    }

    /// Fetch all device statuses in parallel
    @MainActor
    func checkAllDeviceStatuses() async {
        let userList = users.map { (id: $0.id, deviceId: $0.userId) }
        let results = await apiService.fetchAllConnectionStatuses(users: userList)

        for (id, status) in results {
            if status == "online" {
                self.deviceStatuses[id] = "Device is connected"
                self.isBluetoothSetupRequired[id] = false
            } else {
                self.deviceStatuses[id] = "Device cannot connect to the server"
                self.isBluetoothSetupRequired[id] = true
            }
        }
    }

    // Register the app with the server
    func registerApp() {
        Task {
            await apiService.registerApp(appId: getAppId())
            print("App registered successfully")
        }
    }

    // Send a heartbeat signal to the server
    func sendHeartbeat() {
        Task {
            await apiService.sendHeartbeat(appId: getAppId())
            print("Heartbeat sent successfully")
        }
    }

    // Generate a unique app ID and store it in UserDefaults
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
