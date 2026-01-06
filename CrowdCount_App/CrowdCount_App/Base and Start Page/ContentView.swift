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

struct CounterLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var deviceIds: [String]  // Device IDs (userId) in this location
    var overcrowdingLimit: Int?
    var isMapLocation: Bool
    var mapPrimaryDevice: String?
    var colorName: String?  // Color for the folder icon (nil = default orange)

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
}

struct ContentView: View {
    @State private var users: [User] = []
    @State private var currentUserIndex: Int = 0
    @State private var totalCount: Int = 0
    @State private var totalOvercrowdingCount: Int = 0

    // Location state
    @State private var locations: [CounterLocation] = []
    @State private var showLocationList: Bool = false
    @State private var viewingLocationId: UUID? = {
        // Try to restore last viewed location at init time
        if let savedId = UserDefaults.standard.string(forKey: "lastViewingLocationId"),
           let uuid = UUID(uuidString: savedId) {
            return uuid
        }
        return nil
    }()  // nil = all counters, otherwise specific location
    @State private var showSettings: Bool = false
    @State private var selectedUserForSettings: User?
    @State private var userId: String = ""
    @State private var password: String = ""
    @State private var locationName: String = ""
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
    @State private var isBluetoothSetupRequired: [UUID: Bool] = [:]
    @State private var showLoginScreen: Bool = true
    @State private var path = NavigationPath()
    @State private var userPasswords: [UUID: String] = [:] // Store passwords per user
    @StateObject private var alertViewModel = AlertViewModel()

    // Location reconciliation alert
    @State private var showLocationReconciliationAlert: Bool = false
    @State private var reconciliationMessage: String = ""

    // Track newly added device to navigate to it
    @State private var newlyAddedDeviceId: String? = nil

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
                            locationName: $locationName,
                            errorMessage: $errorMessage,
                            setUser: setUser,
                            serverStatus: serverStatus,
                            serverStatusColor: serverStatusColor,
                            alertViewModel: alertViewModel
                        )
                    } else {
                        if users.isEmpty && locations.isEmpty {
                            NoDevicesView(showLoginScreen: $showLoginScreen)
                        } else if let locationId = viewingLocationId {
                            // Viewing a specific location
                            LocationCountersView(
                                locationId: locationId,
                                users: $users,
                                totalCount: $totalCount,
                                userPasswords: $userPasswords,
                                setCurrentCount: setCurrentCount,
                                isBluetoothSetupRequired: $isBluetoothSetupRequired,
                                bluetoothManager: bluetoothManager,
                                sendWiFiCredentials: sendWiFiCredentials,
                                deviceStatuses: $deviceStatuses,
                                serverURL: serverURL,
                                startDeviceStatusCheck: startDeviceStatusCheck,
                                updateFrequencies: $updateFrequencies,
                                logOut: logOut,
                                startLiveCountUpdate: startLiveCountUpdate,
                                locations: $locations,
                                saveLocations: saveLocations,
                                createLocation: { name in _ = createLocation(name: name) },
                                deleteLocation: deleteLocation,
                                viewingLocationId: $viewingLocationId,
                                showLoginScreen: $showLoginScreen,
                                alertViewModel: alertViewModel,
                                newlyAddedDeviceId: $newlyAddedDeviceId
                            )
                        } else {
                            // Viewing all counters
                            if users.isEmpty {
                                // No counters but locations exist - show select location prompt
                                SelectLocationPromptView(
                                    onOpenLocationPicker: { showLocationList = true },
                                    alertViewModel: alertViewModel
                                )
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
                                    startLiveCountUpdate: startLiveCountUpdate,
                                    locations: $locations,
                                    saveLocations: saveLocations,
                                    onOpenLocationPicker: { showLocationList = true },
                                    alertViewModel: alertViewModel
                                )
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if let locationId = viewingLocationId,
                           let location = locations.first(where: { $0.id == locationId }) {
                            // Show location name when viewing a specific location - tappable
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
                        } else if !showLoginScreen && isServerRunning && !users.isEmpty {
                            // Show "All Counters" when viewing all counters - tappable
                            Button(action: { showLocationList = true }) {
                                HStack(spacing: 4) {
                                    Text("All Counters")
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Show app title on login/loading screens
                            AppTitleView(appVersion: appVersion, alertViewModel: alertViewModel)
                        }
                    }
                }
                .onAppear {
                    loadUsers()
                    loadLocations()
                    migrateUsersToLocations()  // Migrate existing users to default location
                    ensureDataConsistency()  // Fix any data sync issues between users and locations
                    startServerStatusCheck()
                    autoLoginIfNeeded()
                    restoreLastViewedLocation()  // Restore last viewed location (after autoLogin sets showLoginScreen)
                    registerApp()
                    startHeartbeat()  // Start sending heartbeats
                    alertViewModel.checkForAlert()
                    reconcileLocationsWithMap()  // Check if locations need to be updated based on map data
                }
                .onChange(of: updateFrequencies) {
                    DispatchQueue.main.async {
                        startLiveCountUpdate()
                    }
                }
                .onChange(of: locations) { _, newLocations in
                    // If current location was deleted, go back to all counters
                    if let currentId = viewingLocationId,
                       !newLocations.contains(where: { $0.id == currentId }) {
                        viewingLocationId = nil
                    }
                }
                .onChange(of: viewingLocationId) { _, newValue in
                    // Persist the currently viewed location
                    if let locationId = newValue {
                        UserDefaults.standard.set(locationId.uuidString, forKey: "lastViewingLocationId")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "lastViewingLocationId")
                    }
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
                .sheet(isPresented: $showLocationList) {
                    LocationPickerView(
                        locations: $locations,
                        users: users,
                        currentlyViewingLocationId: viewingLocationId,
                        onSave: saveLocations,
                        onCreate: { name in
                            _ = createLocation(name: name)
                        },
                        onDelete: deleteLocation,
                        onNavigateToLocation: { location in
                            // Switch to viewing this location
                            viewingLocationId = location.id
                        },
                        onGoToAllCounters: {
                            // Switch to viewing all counters
                            viewingLocationId = nil
                        },
                        mapDeviceIds: [],  // Map data fetched per-location in LocationCountersView
                        isBluetoothSetupRequired: isBluetoothSetupRequired
                    )
                }
                if !showLoginScreen && isServerRunning && networkMonitor.isConnected && viewingLocationId == nil {
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
        .alert("Locations Updated", isPresented: $showLocationReconciliationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(reconciliationMessage)
        }
    }

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

                    // Location button (right) - same style as map button
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
                                .glassEffect()
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

        // Location management
        @Binding var locations: [CounterLocation]
        let saveLocations: () -> Void
        let onOpenLocationPicker: () -> Void
        @ObservedObject var alertViewModel: AlertViewModel

        var body: some View {
            TabView(selection: $currentUserIndex) {
                // Individual user views only (no total count in All Counters view)
                ForEach(Array(users.indices), id: \.self) { index in
                    userView(for: index)
                        .tag(index)
                }

                // Instructions page (rightmost) - tells user to add via a location
                AddToLocationInstructionsView(onOpenLocationPicker: onOpenLocationPicker, alertViewModel: alertViewModel)
                    .tag(users.count)
            }
            .tabViewStyle(PageTabViewStyle())
            .onAppear {
                setupPageControlAppearance()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        NavigationLink(destination: InformationView()) {
                            if #available(iOS 26.0, *) {
                                Image(systemName: "info")
                                    .foregroundColor(.primary)
                            } else {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.leading, alertViewModel.alertExists ? 8 : 0)
                        if alertViewModel.alertExists {
                            Button(action: {
                                alertViewModel.showAlert = true
                            }) {
                                if #available(iOS 26.0, *) {
                                    Image(systemName: "bell.badge.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.red, .primary)
                                } else {
                                    Image(systemName: "bell.badge.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.trailing, 12)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if currentUserIndex < users.count {
                        Button(action: {
                            selectedUserForSettings = users[currentUserIndex]
                            showSettings = true
                        }) {
                            Image(systemName: "gear")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentUserIndex)
        }

        private func setupPageControlAppearance() {
            UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.label
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
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
                },
                alertViewModel: alertViewModel
            )
        }
    }

    /// Instructions view shown in All Counters when user swipes to add - directs them to use locations
    private struct AddToLocationInstructionsView: View {
        let onOpenLocationPicker: () -> Void
        @ObservedObject var alertViewModel: AlertViewModel
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "folder.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.secondary)

                Text("Add counters to a location")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("To add a new counter, go to a specific location first. This helps keep your counters organized.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: onOpenLocationPicker) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Choose a Location")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(.top, 10)

                Text("Or create a new location from the location picker")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
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

    /// View shown when there are locations but no counters - prompts user to select a location
    private struct SelectLocationPromptView: View {
        let onOpenLocationPicker: () -> Void
        @ObservedObject var alertViewModel: AlertViewModel
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "folder.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.secondary)

                Text("No counters added")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Select a location to add your first counter.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: onOpenLocationPicker) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Choose a Location")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(.top, 10)
            }
            .padding()
            .navigationBarItems(leading: HStack(spacing: 14) {
                NavigationLink(destination: InformationView()) {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "info")
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    } else {
                        Image(systemName: "info.circle")
                            .foregroundColor(.primary)
                    }
                }
                .padding(.leading, alertViewModel.alertExists ? 8 : 0)
                if alertViewModel.alertExists {
                    Button(action: {
                        alertViewModel.showAlert = true
                    }) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "bell.badge.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.red, .primary)
                        } else {
                            Image(systemName: "bell.badge.fill")
                                .symbolRenderingMode(.multicolor)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
            })
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

        do {
            let isPasswordCorrect = try await apiService.checkPassword(deviceId: userId, password: password)

            if isPasswordCorrect {
                self.errorMessage = nil
                if !self.users.contains(where: { $0.userId == self.userId }) {
                    // Save values before clearing
                    let deviceId = self.userId
                    let locName = self.locationName

                    let newUser = User(id: UUID(), userId: deviceId, currentCount: 0)
                    self.users.append(newUser)
                    self.userPasswords[newUser.id] = self.password
                    self.calculateTotalCount()
                    self.calculateTotalOvercrowdingCount()

                    // Track newly added device for navigation
                    self.newlyAddedDeviceId = deviceId

                    self.showLoginScreen = false
                    self.startDeviceStatusCheck(for: newUser)
                    await self.fetchCurrentCountAsync(for: newUser.id)
                    self.startLiveCountUpdate()
                    saveUsers()

                    // Create location with the device
                    let newLocation = CounterLocation(
                        id: UUID(),
                        name: locName,
                        deviceIds: [deviceId],
                        overcrowdingLimit: nil,
                        isMapLocation: false,
                        mapPrimaryDevice: nil
                    )
                    self.locations.append(newLocation)
                    saveLocations()

                    // Navigate to the new location
                    self.viewingLocationId = newLocation.id

                    // Clear fields
                    self.userId = ""
                    self.password = ""
                    self.locationName = ""
                } else {
                    self.errorMessage = "Device already added"
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
        if users.isEmpty {
            showLoginScreen = true
        } else {
            showLoginScreen = false
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
            let deviceId = self.users[index].userId
            print("Logging out user with ID: \(userId) (deviceId: \(deviceId)) at index: \(index)")

            self.liveCountUpdateTimers[userId]?.invalidate()
            self.liveCountUpdateTimers.removeValue(forKey: userId)

            self.deviceStatusCheckTimers[userId]?.invalidate()
            self.deviceStatusCheckTimers.removeValue(forKey: userId)

            // Remove device from all locations
            for i in locations.indices {
                locations[i].deviceIds.removeAll { $0 == deviceId }
            }
            // Remove any empty locations that result from this removal
            locations.removeAll { $0.deviceIds.isEmpty }
            saveLocations()

            self.users.remove(at: index)
            
            self.saveUsers()
            
            if self.users.isEmpty {
                // Only show login if both users AND locations are empty
                if self.locations.isEmpty {
                    self.showLoginScreen = true
                }
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

    // MARK: - Location Functions

    func saveLocations() {
        if let encoded = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(encoded, forKey: "locations")
        }
    }

    /// Ensures users and locations data structures are consistent
    func ensureDataConsistency() {
        var needsSave = false

        // 1. Remove deviceIds from locations that don't exist in users
        let validDeviceIds = Set(users.map { $0.userId })
        for i in locations.indices {
            let before = locations[i].deviceIds.count
            locations[i].deviceIds.removeAll { !validDeviceIds.contains($0) }
            if locations[i].deviceIds.count != before {
                needsSave = true
                print("[ensureDataConsistency] Removed orphaned deviceIds from location '\(locations[i].name)'")
            }
        }

        // 2. Remove empty locations (only if there are non-empty ones or no users)
        let emptyLocationCount = locations.filter { $0.deviceIds.isEmpty }.count
        if emptyLocationCount > 0 {
            if users.isEmpty || locations.contains(where: { !$0.deviceIds.isEmpty }) {
                locations.removeAll { $0.deviceIds.isEmpty }
                needsSave = true
                print("[ensureDataConsistency] Removed \(emptyLocationCount) empty locations")
            }
        }

        // 3. Ensure every user's deviceId is in at least one location
        for user in users {
            let isInAnyLocation = locations.contains { $0.deviceIds.contains(user.userId) }
            if !isInAnyLocation {
                if locations.isEmpty {
                    let defaultLocation = CounterLocation(
                        id: UUID(),
                        name: "My Counters",
                        deviceIds: [user.userId],
                        overcrowdingLimit: nil,
                        isMapLocation: false,
                        mapPrimaryDevice: nil
                    )
                    locations.append(defaultLocation)
                } else {
                    locations[0].deviceIds.append(user.userId)
                }
                needsSave = true
                print("[ensureDataConsistency] Added orphaned user '\(user.userId)' to location")
            }
        }

        if needsSave {
            saveLocations()
        }
    }

    func loadLocations() {
        if let savedLocations = UserDefaults.standard.data(forKey: "locations"),
           var decoded = try? JSONDecoder().decode([CounterLocation].self, from: savedLocations) {
            var needsSave = false

            // Clean up any invalid deviceIds (should be short alphanumeric strings only)
            for i in decoded.indices {
                let validIds = decoded[i].deviceIds.filter { deviceId in
                    // Valid device IDs: short, alphanumeric with possible dashes/underscores
                    let isValidLength = deviceId.count <= 20 && deviceId.count > 0
                    let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
                    let isValidChars = deviceId.unicodeScalars.allSatisfy { allowedChars.contains($0) }
                    return isValidLength && isValidChars
                }
                if validIds.count != decoded[i].deviceIds.count {
                    let removed = decoded[i].deviceIds.filter { !validIds.contains($0) }
                    print("[Locations] Removing invalid deviceIds from '\(decoded[i].name)': \(removed)")
                    decoded[i].deviceIds = validIds
                    needsSave = true
                }

                // Clean up location names that are too long (likely corrupted)
                if decoded[i].name.count > 50 {
                    print("[Locations] Truncating long location name: \(decoded[i].name.prefix(30))...")
                    decoded[i].name = "Location \(i + 1)"
                    needsSave = true
                }
            }

            // Remove any locations that have no valid devices and suspicious names
            let validLocations = decoded.filter { location in
                // Keep locations that have devices OR have reasonable names
                !location.deviceIds.isEmpty || location.name.count <= 50
            }
            if validLocations.count != decoded.count {
                print("[Locations] Removed \(decoded.count - validLocations.count) invalid locations")
                decoded = validLocations
                needsSave = true
            }

            locations = decoded
            if needsSave {
                saveLocations()
            }
        }
    }

    /// Validate and restore last viewed location - clears if location no longer exists
    func restoreLastViewedLocation() {
        // viewingLocationId is already set at init from UserDefaults
        // This function validates it exists and clears if not
        if let currentId = viewingLocationId {
            if !locations.contains(where: { $0.id == currentId }) {
                // Location was deleted, go back to all counters
                viewingLocationId = nil
                UserDefaults.standard.removeObject(forKey: "lastViewingLocationId")
            }
        }
    }

    /// Migrate existing users to a default location (for first-time setup)
    func migrateUsersToLocations() {
        // Only migrate if we have users but no locations
        guard !users.isEmpty && locations.isEmpty else { return }

        let defaultLocation = CounterLocation(
            id: UUID(),
            name: "My Counters",
            deviceIds: users.map { $0.userId },
            overcrowdingLimit: nil,
            isMapLocation: false,
            mapPrimaryDevice: nil
        )
        locations.append(defaultLocation)
        saveLocations()
    }

    /// Add a device to a location
    func addDeviceToLocation(deviceId: String, locationId: UUID) {
        if let index = locations.firstIndex(where: { $0.id == locationId }) {
            if !locations[index].deviceIds.contains(deviceId) {
                locations[index].deviceIds.append(deviceId)
                saveLocations()
            }
        }
    }

    /// Remove a device from a location
    func removeDeviceFromLocation(deviceId: String, locationId: UUID) {
        if let index = locations.firstIndex(where: { $0.id == locationId }) {
            locations[index].deviceIds.removeAll { $0 == deviceId }
            saveLocations()
        }
    }

    /// Create a new location
    func createLocation(name: String, deviceIds: [String] = [], isMapLocation: Bool = false, mapPrimaryDevice: String? = nil) -> CounterLocation {
        let newLocation = CounterLocation(
            id: UUID(),
            name: name,
            deviceIds: deviceIds,
            overcrowdingLimit: nil,
            isMapLocation: isMapLocation,
            mapPrimaryDevice: mapPrimaryDevice
        )
        locations.append(newLocation)
        saveLocations()
        return newLocation
    }

    /// Delete a location and all its counters
    func deleteLocation(locationId: UUID) {
        // Find the location and get its device IDs before deleting
        if let location = locations.first(where: { $0.id == locationId }) {
            let deviceIdsToRemove = location.deviceIds

            // Remove all users (counters) that belong to this location
            for deviceId in deviceIdsToRemove {
                if let user = users.first(where: { $0.userId == deviceId }) {
                    logOut(userId: user.id)
                }
            }
        }

        locations.removeAll { $0.id == locationId }
        saveLocations()
    }

    /// Check if local locations match map data and reconcile any mismatches
    /// This handles cases where map locations are created/updated after user already had counters
    func reconcileLocationsWithMap() {
        guard !users.isEmpty else { return }

        guard let url = URL(string: "\(serverURL)/get_all_location_data_with_extra") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let mapLocations = json["locations"] as? [[String: Any]] else {
                return
            }

            // Build map of deviceId -> (mapLocationName, primaryDevice)
            var deviceToMapLocation: [String: String] = [:]
            var deviceToPrimaryDevice: [String: String] = [:]

            for location in mapLocations {
                guard let primaryDeviceId = location["location_device"] as? String,
                      let mapLocationName = location["location_name"] as? String else {
                    continue
                }

                deviceToMapLocation[primaryDeviceId] = mapLocationName
                deviceToPrimaryDevice[primaryDeviceId] = primaryDeviceId

                if let deviceBreakdown = location["device_breakdown"] as? [[String: Any]] {
                    for device in deviceBreakdown {
                        if let deviceId = device["device_id"] as? String {
                            deviceToMapLocation[deviceId] = mapLocationName
                            deviceToPrimaryDevice[deviceId] = primaryDeviceId
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                var movedCounters: [(deviceId: String, fromLocation: String, toLocation: String)] = []
                var locationsToCreate: [String: [String]] = [:] // mapLocationName -> [deviceIds]

                // Check each location for mismatches
                for locationIndex in self.locations.indices {
                    let location = self.locations[locationIndex]
                    var devicesToRemove: [String] = []

                    for deviceId in location.deviceIds {
                        guard deviceId != "Demo" else { continue }

                        if let mapLocationName = deviceToMapLocation[deviceId] {
                            // Device is on the map
                            if location.isMapLocation && location.name != mapLocationName {
                                // Device belongs to a DIFFERENT map location
                                devicesToRemove.append(deviceId)
                                movedCounters.append((deviceId, location.name, mapLocationName))

                                // Queue for new location creation
                                if locationsToCreate[mapLocationName] == nil {
                                    locationsToCreate[mapLocationName] = []
                                }
                                locationsToCreate[mapLocationName]?.append(deviceId)
                            } else if !location.isMapLocation {
                                // Local location but device is now on map - update location to map location
                                // OR move device to its map location if names don't match
                                if location.name != mapLocationName {
                                    devicesToRemove.append(deviceId)
                                    movedCounters.append((deviceId, location.name, mapLocationName))

                                    if locationsToCreate[mapLocationName] == nil {
                                        locationsToCreate[mapLocationName] = []
                                    }
                                    locationsToCreate[mapLocationName]?.append(deviceId)
                                } else {
                                    // Names match - update to map location status
                                    self.locations[locationIndex].isMapLocation = true
                                    self.locations[locationIndex].mapPrimaryDevice = deviceToPrimaryDevice[deviceId]
                                }
                            }
                        }
                    }

                    // Remove devices that need to be moved
                    for deviceId in devicesToRemove {
                        self.locations[locationIndex].deviceIds.removeAll { $0 == deviceId }
                    }
                }

                // Create new locations for moved devices
                for (mapLocationName, deviceIds) in locationsToCreate {
                    // Check if a location with this name already exists
                    if let existingIndex = self.locations.firstIndex(where: { $0.name == mapLocationName && $0.isMapLocation }) {
                        // Add to existing location
                        for deviceId in deviceIds {
                            if !self.locations[existingIndex].deviceIds.contains(deviceId) {
                                self.locations[existingIndex].deviceIds.append(deviceId)
                            }
                        }
                    } else {
                        // Create new location
                        let primaryDevice = deviceIds.first.flatMap { deviceToPrimaryDevice[$0] }
                        let newLocation = CounterLocation(
                            id: UUID(),
                            name: mapLocationName,
                            deviceIds: deviceIds,
                            overcrowdingLimit: nil,
                            isMapLocation: true,
                            mapPrimaryDevice: primaryDevice
                        )
                        self.locations.append(newLocation)
                    }
                }

                // Clean up empty locations (except if user is currently viewing one)
                self.locations.removeAll { location in
                    location.deviceIds.isEmpty && location.id != self.viewingLocationId
                }

                // Save changes
                if !movedCounters.isEmpty {
                    self.saveLocations()

                    // Build alert message
                    let uniqueDestinations = Set(movedCounters.map { $0.toLocation })
                    if uniqueDestinations.count == 1, let destination = uniqueDestinations.first {
                        self.reconciliationMessage = "\(movedCounters.count) counter\(movedCounters.count == 1 ? " was" : "s were") moved to '\(destination)' to match the public map configuration."
                    } else {
                        self.reconciliationMessage = "\(movedCounters.count) counter\(movedCounters.count == 1 ? " was" : "s were") reorganized to match the public map configuration."
                    }
                    self.showLocationReconciliationAlert = true

                    print("[Reconciliation] Moved counters: \(movedCounters)")
                }
            }
        }.resume()
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
