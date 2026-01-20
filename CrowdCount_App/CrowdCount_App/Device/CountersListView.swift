import SwiftUI

/// A view that shows all counters in a stacked list format
struct CountersListView: View {
    let users: [User]
    @Binding var allUsers: [User]
    @Binding var userPasswords: [UUID: String]
    let serverURL: String
    let setCurrentCount: (User, String) -> Void
    let isBluetoothSetupRequired: [UUID: Bool]
    let isCountLoaded: [UUID: Bool]
    @ObservedObject var bluetoothManager: BluetoothManager
    let sendWiFiCredentials: () -> Void
    let isLocationOnMap: Bool
    let mapDeviceIds: Set<String>
    @Binding var updateFrequencies: [UUID: Double]
    let logOut: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    Text("Counters")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    ForEach(users) { user in
                        CounterRowView(
                            user: user,
                            allUsers: $allUsers,
                            userPasswords: $userPasswords,
                            serverURL: serverURL,
                            setCurrentCount: setCurrentCount,
                            isOffline: isBluetoothSetupRequired[user.id] ?? false,
                            isCountLoaded: isCountLoaded[user.id] ?? false,
                            bluetoothManager: bluetoothManager,
                            sendWiFiCredentials: sendWiFiCredentials,
                            isLocationOnMap: isLocationOnMap,
                            isDeviceOnMap: mapDeviceIds.contains(user.userId),
                            updateFrequencies: $updateFrequencies,
                            logOut: logOut
                        )
                    }
                }
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A single counter row in the stacked list
struct CounterRowView: View {
    let user: User
    @Binding var allUsers: [User]
    @Binding var userPasswords: [UUID: String]
    let serverURL: String
    let setCurrentCount: (User, String) -> Void
    let isOffline: Bool
    let isCountLoaded: Bool
    @ObservedObject var bluetoothManager: BluetoothManager
    let sendWiFiCredentials: () -> Void
    let isLocationOnMap: Bool
    let isDeviceOnMap: Bool
    @Binding var updateFrequencies: [UUID: Double]
    let logOut: (UUID) -> Void

    @ObservedObject private var nicknameManager = NicknameManager.shared
    @State private var deviceName: String = ""
    @State private var isEditingName: Bool = false
    @State private var showModifyCount: Bool = false
    @State private var newCount: String = ""
    @State private var previousCount: String? = nil
    @State private var showUndoButton: Bool = false
    @State private var temporaryCount: String? = nil
    @State private var showSettings: Bool = false

    // WiFi setup
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Main row content
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: isOffline ? "wifi.slash" : "wifi")
                    .foregroundColor(isOffline ? .red : .green)
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28)

                // Name and device ID
                VStack(alignment: .leading, spacing: 2) {
                    if isEditingName {
                        HStack {
                            TextField(user.userId, text: $deviceName)
                                .font(.headline)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(6)
                            Button("Done") {
                                saveDeviceName()
                                isEditingName = false
                            }
                            .font(.caption.bold())
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(deviceName.isEmpty ? user.userId : deviceName)
                                .font(.headline)
                            Button(action: { isEditingName = true }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if deviceName != user.userId && !deviceName.isEmpty {
                        Text(user.userId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Warning if not on map
                    if isLocationOnMap && !isDeviceOnMap && user.userId != "Demo" {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("Not on public map")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Count display
                HStack(spacing: 8) {
                    if !isCountLoaded && temporaryCount == nil {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(temporaryCount ?? "\(user.currentCount)")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    if showUndoButton {
                        Button(action: undoCount) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Modify count button
                    Button(action: { showModifyCount.toggle() }) {
                        Image(systemName: "plusminus")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.3))
                            .clipShape(Circle())
                    }

                    // Settings button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Expandable modify count section
            if showModifyCount {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        TextField("New count", text: $newCount)
                            .keyboardType(.numberPad)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(8)

                        Button(action: submitNewCount) {
                            Text("Set")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .disabled(newCount.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            // Connect to WiFi button if offline
            if isOffline {
                Divider()
                    .padding(.horizontal, 16)

                NavigationLink(destination: BluetoothSetupView(
                    wifiSSID: $wifiSSID,
                    wifiPassword: $wifiPassword,
                    bluetoothManager: bluetoothManager,
                    sendWiFiCredentials: sendWiFiCredentials
                )) {
                    HStack {
                        Image(systemName: "wifi.exclamationmark")
                        Text("Connect to WiFi")
                            .font(.subheadline)
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 10)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            deviceName = loadDeviceName()
        }
        .onChange(of: user.currentCount) { _, _ in
            temporaryCount = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                showSettings: $showSettings,
                user: user,
                updateFrequencies: $updateFrequencies,
                userPasswords: $userPasswords,
                logOut: logOut,
                serverURL: serverURL
            )
        }
    }

    // MARK: - Helper Functions

    private func loadDeviceName() -> String {
        nicknameManager.nickname(for: user.userId)
    }

    private func saveDeviceName() {
        nicknameManager.setNickname(deviceName, for: user.userId)
    }

    private func submitNewCount() {
        guard !newCount.isEmpty else { return }
        previousCount = "\(user.currentCount)"
        setCurrentCount(user, newCount)
        temporaryCount = newCount
        showModifyCount = false
        newCount = ""
        showUndoButtonForLimitedTime()
    }

    private func undoCount() {
        if let prevCount = previousCount {
            setCurrentCount(user, prevCount)
            previousCount = nil
            showUndoButton = false
            temporaryCount = nil
        }
    }

    private func showUndoButtonForLimitedTime() {
        showUndoButton = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            showUndoButton = false
        }
    }
}
