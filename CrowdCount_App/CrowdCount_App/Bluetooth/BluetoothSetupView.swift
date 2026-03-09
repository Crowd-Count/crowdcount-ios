import SwiftUI

class CountdownTimer: ObservableObject {
    @Published var counter: Int = 30
    var timer: Timer?

    init() {
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.counter > 0 {
                self.counter -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    func resetTimer() {
        timer?.invalidate()
        counter = 30
        startTimer()
    }
}

struct BluetoothSetupView: View {
    @Binding var wifiSSID: String
    @Binding var wifiPassword: String
    @ObservedObject var bluetoothManager: BluetoothManager
    let sendWiFiCredentials: () -> Void
    var knownDevicePassword: String? = nil

    @StateObject private var countdownTimer = CountdownTimer()

    // QR Scanner State
    @State private var showQRScanner: Bool = true
    @State private var scannedDeviceId: String = ""
    @State private var scannedDeviceSecret: String = ""
    @State private var isScanning: Bool = true

    // Provisioning Form State
    @State private var serverIP: String = "" // Leave blank to use default Tailscale server IP

    // Advanced Settings
    @State private var showAdvanced: Bool = false

    // BLE status polling timer
    @State private var bleStatusTimer: Timer?

    // UI State
    @State private var isLoading: Bool = false
    @State private var showMessage: Bool = false
    @State private var message: String = ""
    @State private var messageColor: Color = .black
    @State private var provisioningStep: ProvisioningStep = .scanQR

    @Environment(\.presentationMode) var presentationMode

    enum ProvisioningStep {
        case scanQR
        case connecting
        case enterCredentials
        case submitting
        case checkingStatus
        case finishing  // brief 100% state before complete
        case complete
    }

    var body: some View {
        NavigationView {
            VStack {
                if provisioningStep == .scanQR {
                    qrScannerView
                } else if provisioningStep == .connecting {
                    connectingView
                } else if provisioningStep == .enterCredentials {
                    credentialsFormView
                } else if provisioningStep == .submitting || provisioningStep == .checkingStatus || provisioningStep == .finishing {
                    submittingView
                } else if provisioningStep == .complete {
                    completeView
                }
            }
            .padding()
        }
        .navigationTitle("Counter Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isScanning) { oldValue, newValue in
            if !newValue && !scannedDeviceId.isEmpty {
                // QR code scanned successfully
                bluetoothManager.deviceId = scannedDeviceId
                bluetoothManager.deviceSecret = scannedDeviceSecret
                provisioningStep = .connecting
                bluetoothManager.initializeCentralManager()

                // Wait for Bluetooth to be ready, then start scanning
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    bluetoothManager.startScanning()
                }
            }
        }
        .onChange(of: bluetoothManager.isConnected) { oldValue, newValue in
            if newValue {
                countdownTimer.timer?.invalidate()
                provisioningStep = .enterCredentials
            } else if provisioningStep == .connecting {
                countdownTimer.resetTimer()
            } else if !newValue && provisioningStep == .submitting {
                // BLE disconnected during provisioning — stop BLE timer, fall back to HTTP polling
                stopBLEStatusTimer()
                startHTTPPolling()
            }
        }
        .onChange(of: bluetoothManager.deviceStatus) { oldValue, newValue in
            guard provisioningStep == .submitting else { return }
            switch newValue {
            case 3: // WIFI_FAILED
                stopBLEStatusTimer()
                message = "WiFi connection failed. Please check your credentials and try again."
                messageColor = .red
                showMessage = true
                isLoading = false
                provisioningStep = .enterCredentials
            case 4: // SUCCESS
                stopBLEStatusTimer()
                startHTTPPolling()
            default:
                break
            }
        }
    }

    // MARK: - QR Scanner View

    var qrScannerView: some View {
        VStack {
            Spacer()
            Image(systemName: "qrcode.viewfinder")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.primary)
                .padding()

            Text("Scan Counter QR Code")
                .font(.title2)
                .bold()
                .padding()

            Text("Point your camera at the QR code on your Crowd Counter")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                showQRScanner = true
            }) {
                Text("Scan QR Code")
                    .padding()
                    .background(Color.blue.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
            }
            .padding()
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(
                    scannedDeviceId: $scannedDeviceId,
                    scannedDeviceSecret: $scannedDeviceSecret,
                    isScanning: $isScanning
                )
            }

            Spacer()
        }
    }

    // MARK: - Connecting View

    var connectingView: some View {
        VStack {
            Spacer()
            Text("Connecting to Counter")
                .font(.title2)
                .bold()
                .padding()

            Text("Device ID: \(scannedDeviceId)")
                .foregroundColor(.secondary)
                .padding(.bottom)

            ProgressView()
                .scaleEffect(1.5)
                .padding()

            if countdownTimer.counter > 0 {
                Text("\(countdownTimer.counter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack {
                    Text("Still not connecting?")
                        .font(.title3)
                        .bold()
                        .padding(.top)

                    Text("Try unplugging the counter and plugging it back in, wait a few seconds and then tap 'Retry'")
                        .foregroundColor(.secondary)
                        .padding()
                        .multilineTextAlignment(.center)

                    Button(action: {
                        countdownTimer.resetTimer()
                        bluetoothManager.stopScanning()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            bluetoothManager.startScanning()
                        }
                    }) {
                        Text("Retry")
                            .padding()
                            .background(Color.blue.opacity(0.75))
                            .foregroundColor(.primary)
                            .cornerRadius(20)
                    }
                    .padding(10)
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(25)
                .padding()
            }

            Spacer()

            Text("Please ensure Bluetooth is on and the counter is powered and in range")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .font(.caption)
                .padding(.bottom)
        }
    }

    // MARK: - Credentials Form View

    var credentialsFormView: some View {
        VStack {
            Text("Enter Network Configuration")
                .font(.title3)
                .bold()
                .padding()
            Text("Device: \(scannedDeviceId)")
                .foregroundColor(.secondary)
                .padding(.bottom)
            Text("Make sure to stay in range of the counter")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.bottom)
            ScrollView {
                VStack(spacing: 15) {
                    // WiFi SSID — picker or manual entry
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("WiFi Network")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if bluetoothManager.isScanningWifi {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Button(action: {
                                    bluetoothManager.scanForWifiNetworks()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption2)
                                        Text("Scan")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }

                        if !bluetoothManager.availableNetworks.isEmpty {
                            // Network picker list
                            VStack(spacing: 0) {
                                ForEach(bluetoothManager.availableNetworks, id: \.ssid) { network in
                                    Button(action: {
                                        wifiSSID = network.ssid
                                    }) {
                                        HStack {
                                            Image(systemName: "wifi", variableValue: Double(network.signal) / 100.0)
                                                .foregroundColor(.secondary)
                                                .frame(width: 20)
                                            Text(network.ssid)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            if wifiSSID == network.ssid {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    if network.ssid != bluetoothManager.availableNetworks.last?.ssid {
                                        Divider().padding(.leading, 40)
                                    }
                                }
                            }
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(12)

                            // Manual entry fallback
                            Button(action: {
                                wifiSSID = ""
                                bluetoothManager.availableNetworks = []
                            }) {
                                Text("Enter manually instead")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            // Manual text field
                            TextField("WiFi SSID", text: $wifiSSID)
                                .padding()
                                .background(Color.secondary.opacity(0.25))
                                .cornerRadius(15)
                                .autocapitalization(.none)
                                .textContentType(.username)
                                .disableAutocorrection(true)
                        }
                    }

                    // WiFi Password
                    VStack(alignment: .leading) {
                        Text("WiFi Password")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("WiFi Password", text: $wifiPassword)
                            .padding()
                            .background(Color.secondary.opacity(0.25))
                            .cornerRadius(15)
                            .autocapitalization(.none)
                            .textContentType(.password)
                    }

                    // Advanced Settings Toggle
                    Button(action: {
                        withAnimation {
                            showAdvanced.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("Advanced Settings")
                                .font(.subheadline)
                            Spacer()
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    }
                    .padding(.top, 10)

                    if showAdvanced {
                        VStack(spacing: 15) {
                            // Warning Message
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text("For Development Use Only")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.orange)
                                    Text("Changing these values incorrectly will prevent your counter from connecting")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(10)

                            // Server IP
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Server IP (Tailscale)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if serverIP.isEmpty {
                                        Text("Using default IP")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Custom IP set")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                                TextField("Leave blank to use default IP", text: $serverIP)
                                    .padding()
                                    .background(Color.secondary.opacity(0.25))
                                    .cornerRadius(15)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        .transition(.opacity)
                    }

                    if isLoading {
                        ProgressView()
                            .padding()
                    } else {
                        Button(action: submitCredentials) {
                            Text("Submit Configuration")
                                .bold()
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.75))
                                .foregroundColor(.primary)
                                .cornerRadius(20)
                        }
                    }

                    if showMessage {
                        Text(message)
                            .foregroundColor(messageColor)
                            .padding()
                    }

                    if let connectionError = bluetoothManager.connectionError {
                        Text(connectionError)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Submitting View

    var submittingView: some View {
        let (statusText, subtitleText): (String, String) = {
            if provisioningStep == .finishing {
                return ("Counter is online!", "")
            } else if provisioningStep == .checkingStatus {
                return ("Checking Counter Status...", "Verifying connection to server")
            } else {
                return (statusDisplayText, "Please stay in range of the counter")
            }
        }()

        return BluetoothSetupView.provisioningProgressView(
            progress: provisioningProgress,
            iconName: statusIconName,
            statusText: statusText,
            subtitleText: subtitleText
        )
    }

    private var provisioningProgress: Double {
        if provisioningStep == .finishing {
            return 1.0
        }
        if provisioningStep == .checkingStatus {
            return 0.90
        }
        switch bluetoothManager.deviceStatus {
        case 2: return 0.35    // Connecting to WiFi
        case 5: return 0.60    // WiFi connected
        case 4: return 0.80    // Success, about to verify
        default: return 0.15   // Sending credentials
        }
    }

    private var statusDisplayText: String {
        switch bluetoothManager.deviceStatus {
        case 2:
            return "Connecting to WiFi..."
        case 5:
            return "WiFi connected! Configuring counter..."
        case 4:
            return "Almost done! Verifying connection..."
        default:
            return "Sending credentials..."
        }
    }

    private var statusIconName: String {
        if provisioningStep == .finishing {
            return "checkmark.circle"
        }
        if provisioningStep == .checkingStatus {
            return "server.rack"
        }
        switch bluetoothManager.deviceStatus {
        case 2: return "wifi"
        case 5: return "wifi"
        case 4: return "checkmark.icloud"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    // MARK: - Complete View

    var completeView: some View {
        VStack {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
                .padding()

            Text("Success!")
                .font(.title)
                .bold()
                .padding()

            Text("Your counter is now online and streaming")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Button(action: {
                bluetoothManager.disconnect()
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Done")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Functions

    func submitCredentials() {
        // Validation
        guard !wifiSSID.isEmpty else {
            message = "Please enter WiFi network name"
            messageColor = .red
            showMessage = true
            return
        }

        guard !wifiPassword.isEmpty else {
            message = "Please enter WiFi password"
            messageColor = .red
            showMessage = true
            return
        }

        // Server IP has a default value, no need to validate
        // Stream name is optional

        isLoading = true
        showMessage = false
        provisioningStep = .submitting

        // Send all credentials via Bluetooth
        bluetoothManager.sendProvisioningData(
            ssid: wifiSSID,
            password: wifiPassword,
            tailscaleKey: "",
            serverIP: serverIP.isEmpty ? "" : serverIP,
            streamName: nil
        )

        // Start BLE status polling every 2 seconds
        startBLEStatusTimer()
    }

    // MARK: - BLE Status Polling

    func startBLEStatusTimer() {
        stopBLEStatusTimer()
        bleStatusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.bluetoothManager.readDeviceStatus()
        }
    }

    func stopBLEStatusTimer() {
        bleStatusTimer?.invalidate()
        bleStatusTimer = nil
    }

    func startHTTPPolling() {
        // Start HTTP polling immediately with 5s intervals, 24 attempts = ~2 minutes
        provisioningStep = .checkingStatus
        checkDeviceStatus(attemptsRemaining: 23, interval: 5)
    }

    // Extracted submitting content so previews can reuse it
    static func provisioningProgressView(
        progress: Double,
        iconName: String,
        statusText: String,
        subtitleText: String
    ) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)

                Text(statusText)
                    .font(.title3)
                Text(subtitleText)
                    .foregroundColor(.secondary)

                // Pill progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 10)
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: max(10, geo.size.width * progress), height: 10)
                            .animation(.easeInOut(duration: 0.6), value: progress)
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 40)

                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 4)
            }

            Spacer()

            Text("This process can take up to 2 minutes")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
    }

    func checkDeviceStatus(attemptsRemaining: Int, interval: TimeInterval) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/connection_status") else {
            self.message = "Server error, please try again later"
            self.messageColor = .red
            self.showMessage = true
            self.isLoading = false
            self.provisioningStep = .enterCredentials
            return
        }

        // Use the password passed in from the parent view (which already has the device credentials).
        // Fall back to a cc_devices lookup in case knownDevicePassword wasn't provided.
        let devicePassword: String? = knownDevicePassword ?? {
            if let data = UserDefaults.standard.data(forKey: "cc_devices"),
               let devices = try? JSONDecoder().decode([Device].self, from: data) {
                return devices.first(where: { $0.deviceId == scannedDeviceId })?.password
            }
            return nil
        }()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var body: [String: Any] = ["device_id": scannedDeviceId]
        if let password = devicePassword {
            body["password"] = password
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    if attemptsRemaining > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                            self.checkDeviceStatus(attemptsRemaining: attemptsRemaining - 1, interval: interval)
                        }
                    } else {
                        self.message = "Network error: \(error.localizedDescription)"
                        self.messageColor = .red
                        self.showMessage = true
                        self.isLoading = false
                        self.provisioningStep = .enterCredentials
                    }
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let status = json["status"] as? String {
                        if status == "online" {
                            self.isLoading = false
                            self.provisioningStep = .finishing
                            // Show 100% for a moment, then transition to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                self.provisioningStep = .complete
                            }
                        } else if attemptsRemaining > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                                self.checkDeviceStatus(attemptsRemaining: attemptsRemaining - 1, interval: interval)
                            }
                        } else {
                            self.message = "Counter is still offline. Please check WiFi credentials and try again."
                            self.messageColor = .red
                            self.showMessage = true
                            self.isLoading = false
                            self.provisioningStep = .enterCredentials
                        }
                    } else {
                        if attemptsRemaining > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                                self.checkDeviceStatus(attemptsRemaining: attemptsRemaining - 1, interval: interval)
                            }
                        } else {
                            self.message = "Unexpected response from server"
                            self.messageColor = .red
                            self.showMessage = true
                            self.isLoading = false
                            self.provisioningStep = .enterCredentials
                        }
                    }
                } else {
                    if attemptsRemaining > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                            self.checkDeviceStatus(attemptsRemaining: attemptsRemaining - 1, interval: interval)
                        }
                    } else {
                        self.message = "Server error. Please wait and try again."
                        self.messageColor = .red
                        self.showMessage = true
                        self.isLoading = false
                        self.provisioningStep = .enterCredentials
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Provisioning Progress Preview

/// Animated preview that cycles through all provisioning stages
struct ProvisioningProgressPreview: View {
    @State private var stage = 0
    @State private var showComplete = false

    private let stages: [(progress: Double, icon: String, status: String, subtitle: String)] = [
        (0.15, "antenna.radiowaves.left.and.right", "Sending credentials...", "Please stay in range of the counter"),
        (0.35, "wifi", "Connecting to WiFi...", "Please stay in range of the counter"),
        (0.60, "wifi", "WiFi connected! Configuring counter...", "Please stay in range of the counter"),
        (0.80, "checkmark.icloud", "Almost done! Verifying connection...", "Please stay in range of the counter"),
        (0.90, "server.rack", "Checking Counter Status...", "Verifying connection to server"),
        (1.0, "checkmark.circle", "Counter is online!", ""),
    ]

    var body: some View {
        let s = stages[stage]
        VStack {
            if showComplete {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.green)
                        .padding()
                    Text("Success!")
                        .font(.title)
                        .bold()
                        .padding()
                    Text("Your counter is now online and streaming")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                BluetoothSetupView.provisioningProgressView(
                    progress: s.progress,
                    iconName: s.icon,
                    statusText: s.status,
                    subtitleText: s.subtitle
                )
            }

            // Stage picker at bottom for manual control
            Divider()
            HStack {
                ForEach(0..<stages.count, id: \.self) { i in
                    Button(action: {
                        withAnimation { stage = i; showComplete = false }
                    }) {
                        Text("\(i + 1)")
                            .font(.caption)
                            .bold()
                            .frame(width: 32, height: 32)
                            .background(i == stage && !showComplete ? Color.blue : Color.secondary.opacity(0.2))
                            .foregroundColor(i == stage && !showComplete ? .white : .primary)
                            .clipShape(Circle())
                    }
                }
                Button(action: {
                    withAnimation { showComplete = true }
                }) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .bold()
                        .frame(width: 32, height: 32)
                        .background(showComplete ? Color.green : Color.secondary.opacity(0.2))
                        .foregroundColor(showComplete ? .white : .primary)
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                withAnimation {
                    if showComplete {
                        // Reset to beginning
                        showComplete = false
                        stage = 0
                    } else if stage < stages.count - 1 {
                        stage += 1
                    } else {
                        // At 100%, show complete screen next
                        showComplete = true
                    }
                }
            }
        }
    }
}

#Preview("Provisioning Progress") {
    ProvisioningProgressPreview()
}
