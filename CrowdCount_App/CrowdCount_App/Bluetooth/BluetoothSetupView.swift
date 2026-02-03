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
                } else if provisioningStep == .submitting || provisioningStep == .checkingStatus {
                    submittingView
                } else if provisioningStep == .complete {
                    completeView
                }
            }
            .padding()
        }
        .navigationTitle("Device Setup")
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

            Text("Scan Device QR Code")
                .font(.title2)
                .bold()
                .padding()

            Text("Point your camera at the QR code on your CrowdCount device")
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
            Text("Connecting to Device")
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

                    Text("Try powering off the device and turning it back on, then tap 'Retry'")
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

            Text("Please ensure Bluetooth is on and the device is powered and in range")
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
            Text("Make sure to stay in range of the device")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.bottom)
            ScrollView {
                VStack(spacing: 15) {
                    // WiFi SSID
                    VStack(alignment: .leading) {
                        Text("WiFi Network Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("WiFi SSID", text: $wifiSSID)
                            .padding()
                            .background(Color.secondary.opacity(0.25))
                            .cornerRadius(15)
                            .autocapitalization(.none)
                            .textContentType(.username)
                            .disableAutocorrection(true)
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
                                    Text("Changing these values incorrectly will prevent your device from connecting")
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
        VStack {
            Spacer()

            if provisioningStep == .submitting {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text("Configuring Device...")
                    .font(.title3)
                    .padding()
                Text("This may take up to 2 minutes")
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text("Checking Device Status...")
                    .font(.title3)
                    .padding()
                Text("Verifying connection to server")
                    .foregroundColor(.secondary)
            }

            Spacer()
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

            Text("Your device is now online and streaming")
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

        // Wait for device to configure (120 seconds), then check status with retries
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            isLoading = false
            provisioningStep = .checkingStatus
            checkDeviceStatus(retriesRemaining: 3)
        }
    }

    func checkDeviceStatus(retriesRemaining: Int = 0) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/connection_status") else {
            self.message = "Server error, please try again later"
            self.messageColor = .red
            self.showMessage = true
            self.provisioningStep = .enterCredentials
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": scannedDeviceId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    if retriesRemaining > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                            self.checkDeviceStatus(retriesRemaining: retriesRemaining - 1)
                        }
                    } else {
                        self.message = "Network error: \(error.localizedDescription)"
                        self.messageColor = .red
                        self.showMessage = true
                        self.provisioningStep = .enterCredentials
                    }
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let status = json["status"] as? String {
                        if status == "online" {
                            // Success!
                            self.provisioningStep = .complete
                        } else if retriesRemaining > 0 {
                            // Not online yet, retry after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                                self.checkDeviceStatus(retriesRemaining: retriesRemaining - 1)
                            }
                        } else {
                            // Still offline after all retries
                            self.message = "Device is still offline. Please check WiFi credentials and try again."
                            self.messageColor = .red
                            self.showMessage = true
                            self.provisioningStep = .enterCredentials
                        }
                    } else {
                        self.message = "Unexpected response from server"
                        self.messageColor = .red
                        self.showMessage = true
                        self.provisioningStep = .enterCredentials
                    }
                } else {
                    if retriesRemaining > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                            self.checkDeviceStatus(retriesRemaining: retriesRemaining - 1)
                        }
                    } else {
                        self.message = "Server error. Please wait and try again."
                        self.messageColor = .red
                        self.showMessage = true
                        self.provisioningStep = .enterCredentials
                    }
                }
            }
        }.resume()
    }
}
