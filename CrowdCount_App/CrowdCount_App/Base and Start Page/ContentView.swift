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
    @State private var deviceStatuses: [UUID: String] = [:]
    @State private var isBluetoothSetupRequired: [UUID: Bool] = [:]
    @State private var showLoginScreen: Bool = true
    @State private var path: [String] = []
    @State private var userPasswords: [UUID: String] = [:] // Store passwords per user
    @ObservedObject private var alertViewModel = AlertViewModel()
    
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
                        if users.isEmpty {
                            NoDevicesView(showLoginScreen: $showLoginScreen)
                        } else {
                            UsersTabView(
                                users: $users,
                                currentUserIndex: $currentUserIndex,
                                totalCount: $totalCount,
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
                }
                .onChange(of: updateFrequencies) {
                    DispatchQueue.main.async {
                        startLiveCountUpdate()
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
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
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
                    Text("\(Text("[crowdcount.tech](https://www.crowdcount.tech)"))")
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
                    Image(colorScheme == .dark ? .transparentLogo : .transparentLogoBlack)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 125, height: 125)
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
                if users.count > 1 {
                    TotalCountView(totalCount: totalCount)
                        .tag(0)
                }
                ForEach(users.indices, id: \.self) { index in
                    userView(for: index)
                        .tag(users.count > 1 ? index + 1 : index)
                }
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
                serverURL: serverURL,
                userPasswords: $userPasswords, // Pass userPasswords
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
                    HStack {
                        Text("CrowdCount")
                            .font(.headline)
                        if alertViewModel.alertExists {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .padding(.top, 0)
                                .padding(.bottom, 0)
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
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            checkServerStatus()
        }
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
    }

    func checkServerStatus() {
        let urlString = "\(serverURL)/healthcheck"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.serverStatus = "Invalid server URL"
                self.serverStatusColor = .red
                self.isServerRunning = false
            }
            return
        }

        URLSession.shared.dataTask(with: url) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.serverStatus = "Server is running"
                    self.serverStatusColor = .gray
                    self.isServerRunning = true
                } else {
                    self.serverStatus = "Server is not running"
                    self.serverStatusColor = .red
                    self.isServerRunning = false
                }
            }
        }.resume()
    }

    func startHeartbeat() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.sendHeartbeat()
        }
    }

    func sendWiFiCredentials() {
        bluetoothManager.sendWiFiCredentials(ssid: wifiSSID, password: wifiPassword)
    }

    func autoLoginIfNeeded() {
        if !userId.isEmpty && !password.isEmpty {
            setUser()
        } else {
            checkStoredUsers()
        }
    }

    func fetchCurrentCount(for userId: UUID) {
        guard let userIndex = users.firstIndex(where: { $0.id == userId }) else {
            print("User not found for ID: \(userId)")
            return
        }

        let user = users[userIndex]
        let urlString = "\(serverURL)/currentcount?user_id=\(user.userId)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for user: \(user.userId)")
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received for user: \(user.userId)")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let count = json["current_count"] as? Int {
                    DispatchQueue.main.async {
                        if let updatedIndex = self.users.firstIndex(where: { $0.id == userId }) {
                            self.users[updatedIndex].currentCount = count
                            self.calculateTotalCount()
                        }
                    }
                } else {
                    print("Invalid response format for user: \(user.userId)")
                }
            } catch {
                print("Error parsing response for user: \(user.userId)")
            }
        }.resume()
    }

    func setCurrentCount(user: User, count: String) {
        print("setCurrentCount called for user: \(user.userId) with count: \(count)")

        guard !count.isEmpty, let newCount = Int(count) else {
            errorMessage = "Please enter a valid count"
            print("Error: Invalid count")
            return
        }

        let currentUserId = user.userId
        guard let password = userPasswords[user.id] else {
            errorMessage = "Password not found for user"
            print("Error: Password not found for user \(user.userId)")
            return
        }

        print("Setting current count for user: \(currentUserId) to \(newCount) with password: \(password)")

        let urlString = "\(serverURL)/currentcount"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            print("Error: Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let bodyData = "user_id=\(currentUserId)&password=\(password)&new_count=\(newCount)"
        request.httpBody = bodyData.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        print("Sending request to \(urlString) with body data: \(bodyData)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                print("Network error: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unexpected server response"
                }
                print("Unexpected server response")
                return
            }

            if httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.fetchCurrentCount(for: user.id)
                    self.showNewCountField = false
                    print("Successfully updated count for user: \(currentUserId)")
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to update count"
                }
                print("Failed to update count, status code: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    func setUser() {
        guard !userId.isEmpty else {
            errorMessage = "Please enter a Device ID"
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Please enter a Password"
            return
        }

        let urlString = "\(serverURL)/check_password?user_id=\(userId)&password=\(password)"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid user"
                }
                return
            }

            if httpResponse.statusCode == 404 {
                DispatchQueue.main.async {
                    self.errorMessage = "Device ID does not exist"
                }
            } else if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let isPasswordCorrect = json["is_password_correct"] as? Bool, isPasswordCorrect {
                    DispatchQueue.main.async {
                        self.errorMessage = nil
                        if !self.users.contains(where: { $0.userId == self.userId }) {
                            let newUser = User(id: UUID(), userId: self.userId, currentCount: 0)
                            self.users.append(newUser)
                            self.userPasswords[newUser.id] = self.password
                            self.calculateTotalCount()
                            self.showLoginScreen = false
                            self.startDeviceStatusCheck(for: newUser)
                            self.fetchCurrentCount(for: newUser.id)
                            DispatchQueue.main.async {
                                self.startLiveCountUpdate()
                            }
                            saveUsers()
                        } else {
                            self.errorMessage = "Device already added"
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Incorrect password"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unexpected response from server"
                }
            }
        }.resume()
    }

    func checkStoredUsers() {
        if let savedUsers = UserDefaults.standard.object(forKey: "users") as? Data {
            let decoder = JSONDecoder()
            if let decodedUsers = try? decoder.decode([User].self, from: savedUsers) {
                users = decodedUsers
                for user in users {
                    startDeviceStatusCheck(for: user)
                }
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
        let urlString = "\(serverURL)/connection_status?user_id=\((user.userId))"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.deviceStatuses[user.id] = "Invalid URL"
                self.isBluetoothSetupRequired[user.id] = true
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.deviceStatuses[user.id] = "Network error: \(error.localizedDescription)"
                    self.isBluetoothSetupRequired[user.id] = true
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let status = json["status"] as? String {
                        if status == "online" {
                            self.deviceStatuses[user.id] = "Device is connected"
                            self.isBluetoothSetupRequired[user.id] = false
                        } else {
                            self.deviceStatuses[user.id] = "Device cannot connect to the server"
                            self.isBluetoothSetupRequired[user.id] = true
                        }
                    } else {
                        self.deviceStatuses[user.id] = "Unexpected response format"
                        self.isBluetoothSetupRequired[user.id] = true
                    }
                } else {
                    self.deviceStatuses[user.id] = "Device cannot connect to the server"
                    self.isBluetoothSetupRequired[user.id] = true
                }
            }
        }.resume()
    }

    // Register the app with the server
    func registerApp() {
        let appId = getAppId()
        let urlString = "\(serverURL)/register"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["app_id": appId]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Register app error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("App registered successfully with appId: \(appId)")
            } else {
                print("Failed to register app")
            }
        }.resume()
    }

    // Send a heartbeat signal to the server
    func sendHeartbeat() {
        let appId = getAppId()
        let urlString = "\(serverURL)/heartbeat"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["app_id": appId]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Heartbeat error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Heartbeat sent successfully")
            } else {
                print("Failed to send heartbeat")
            }
        }.resume()
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
