import SwiftUI

struct UserView: View {
    @Binding var user: User
    @Binding var users: [User]
    let serverURL: String
    @Binding var userPasswords: [UUID: String]

    @Environment(\.colorScheme) var colorScheme
    
    @State private var showNewCountField: Bool = false

    @State private var newCount: String = ""
    
    @State private var deviceName: String = ""
    @State private var isEditingName: Bool = false
    @State private var previousCount: String? = nil
    @State private var showUndoButton: Bool = false
    let setCurrentCount: (User, String) -> Void
    @Binding var isBluetoothSetupRequired: Bool
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""
    let sendWiFiCredentials: () -> Void
    @Binding var deviceStatusMessage: String
    @Binding var showSettings: Bool
    @Binding var updateFrequencies: [UUID: Double]
    let logOut: (UUID) -> Void
    let showSettingsForUser: () -> Void
    @ObservedObject var alertViewModel: AlertViewModel
    @State private var temporaryCount: String? = nil

    // Map status indicators
    let isLocationOnMap: Bool  // Is the parent location on the public map
    let isDeviceOnMap: Bool    // Is this specific device on the map
    let isCountLoaded: Bool    // Track if initial count has been fetched

    init(
        user: Binding<User>,
        users: Binding<[User]>,
        serverURL: String,
        userPasswords: Binding<[UUID: String]>,
        setCurrentCount: @escaping (User, String) -> Void,
        isBluetoothSetupRequired: Binding<Bool>,
        bluetoothManager: BluetoothManager,
        sendWiFiCredentials: @escaping () -> Void,
        deviceStatusMessage: Binding<String>,
        showSettings: Binding<Bool>,
        updateFrequencies: Binding<[UUID: Double]>,
        logOut: @escaping (UUID) -> Void,
        showSettingsForUser: @escaping () -> Void,
        alertViewModel: AlertViewModel,
        isLocationOnMap: Bool = false,
        isDeviceOnMap: Bool = true,
        isCountLoaded: Bool = true
    ) {
        self._user = user
        self._users = users
        self.serverURL = serverURL
        self._userPasswords = userPasswords
        self.setCurrentCount = setCurrentCount
        self._isBluetoothSetupRequired = isBluetoothSetupRequired
        self.bluetoothManager = bluetoothManager
        self.sendWiFiCredentials = sendWiFiCredentials
        self._deviceStatusMessage = deviceStatusMessage
        self._showSettings = showSettings
        self._updateFrequencies = updateFrequencies
        self.logOut = logOut
        self.showSettingsForUser = showSettingsForUser
        self.alertViewModel = alertViewModel
        self.isLocationOnMap = isLocationOnMap
        self.isDeviceOnMap = isDeviceOnMap
        self.isCountLoaded = isCountLoaded
    }

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack {
            if !isBluetoothSetupRequired {
                Image(systemName: "wifi")
                    .foregroundColor(.green)
                    .font(.system(size: 25))
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
                    .font(.system(size: 25))
                    .symbolRenderingMode(.hierarchical)
            }
            
            Text((!isBluetoothSetupRequired) ? "Live Count for:" : "Last Count for:")
                .font(.callout)
                .padding(.top)
            
            HStack {
                if isEditingName {
                    HStack{
                        TextField("\(user.userId)", text: $deviceName, onCommit: {
                            saveDeviceName()
                            isEditingName = false
                        })
                        .padding(10)
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                        Button(action: {
                            saveDeviceName()
                            isEditingName = false
                        }) {
                            Text("Done")
                                .foregroundColor(.primary)
                                .bold()
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    Text(deviceName.isEmpty ? user.userId : deviceName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Button(action: {
                        isEditingName.toggle()
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                    }
                }
            }

            // Warning if device is not on the public map (only show for map locations)
            if isLocationOnMap && !isDeviceOnMap && user.userId != "Demo" {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Not on public map")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 2)
            }

            HStack {
                if !isCountLoaded && temporaryCount == nil {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(height: 50)
                } else {
                    Text(temporaryCount ?? "\(user.currentCount)")
                        .font(.system(size: 50))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if showUndoButton {
                    Button(action: undoCount) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            
            HStack {
                Button(action: {
                    showNewCountField.toggle()
                }) {
                    HStack {
                        if !showNewCountField {
                            Image(systemName: "number")
                                .foregroundColor(.primary)
                        }
                        Text(showNewCountField ? "Cancel" : "Modify Count")
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(showNewCountField ? 0.25 : 0.5))
                    .cornerRadius(20)
                }
                
                if showNewCountField {
                    Button(action: {
                        savePreviousCount()
                        setCurrentCount(user, newCount)
                        temporaryCount = newCount // Show the inputted number
                        showNewCountField.toggle()
                        showUndoButtonForLimitedTime()
                    }) {
                        Text("Submit")
                            .padding()
                            .background(Color.secondary.opacity(0.75))
                            .foregroundColor(.primary)
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.top, 5)
            
            if showNewCountField {
                HStack {
                    TextField("Enter New Count", text: $newCount)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                        .keyboardType(.numberPad)
                }
                .padding(.horizontal, 20)
            }

            if isBluetoothSetupRequired {
                NavigationLink(destination: CounterPlacementGuideView(
                    wifiSSID: $wifiSSID,
                    wifiPassword: $wifiPassword,
                    bluetoothManager: bluetoothManager,
                    sendWiFiCredentials: sendWiFiCredentials
                )) {
                    Text("Connect Device to WiFi")
                        .padding()
                        .background(Color.red.opacity(0.75))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                }
                .padding(.top, 10)
            }
            
            // Exit Demo button - commented out
            // if user.userId == "Demo"{
            //     Spacer()
            //     HStack {
            //         Button(action: {
            //             logOut(user.id)
            //             print("Remove Device pressed.")
            //         }) {
            //             Text("Exit Demo")
            //                 .padding()
            //                 .bold()
            //                 .background(Color.secondary.opacity(0.2))
            //                 .foregroundColor(.red)
            //                 .cornerRadius(20)
            //         }
            //     }
            //     .padding(.bottom, 40)
            // }

            Spacer().frame(height: 30)
        }
        .padding()
        .onAppear {
            deviceName = loadDeviceName()
        }
        .onChange(of: user.currentCount) { oldValue, newValue in
            temporaryCount = nil // Clear temporary count when user count updates
        }
        
    }
    
    func saveDeviceName() {
        UserDefaults.standard.set(deviceName, forKey: user.id.uuidString)
    }
    
    func loadDeviceName() -> String {
        return UserDefaults.standard.string(forKey: user.id.uuidString) ?? user.userId
    }
    
    func savePreviousCount() {
        previousCount = "\(user.currentCount)"
    }
    
    func undoCount() {
        if let prevCount = previousCount {
            setCurrentCount(user, prevCount)
            previousCount = nil
            showUndoButton = false
            temporaryCount = nil
        }
    }
    
    func showUndoButtonForLimitedTime() {
        showUndoButton = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            showUndoButton = false
        }
    }
}

// MARK: - Preview

#Preview("User View") {
    NavigationView {
        UserView(
            user: .constant(User(id: UUID(), userId: "T0000", currentCount: 42)),
            users: .constant([User(id: UUID(), userId: "T0000", currentCount: 42)]),
            serverURL: "https://api.example.com",
            userPasswords: .constant([:]),
            setCurrentCount: { _, _ in },
            isBluetoothSetupRequired: .constant(false),
            bluetoothManager: BluetoothManager(),
            sendWiFiCredentials: {},
            deviceStatusMessage: .constant("Connected"),
            showSettings: .constant(false),
            updateFrequencies: .constant([:]),
            logOut: { _ in },
            showSettingsForUser: {},
            alertViewModel: AlertViewModel()
        )
        .environmentObject(AppSettings())
    }
}

