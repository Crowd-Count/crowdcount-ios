import SwiftUI

class CountdownTimer: ObservableObject {
    @EnvironmentObject var appSettings: AppSettings
    @Published var counter: Int = 30
    var timer: Timer?

    init() {
        startTimer()
    }

    func startTimer() {
        // Invalidate any existing timer before starting a new one
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

    @State private var isLoading: Bool = false
    @State private var showMessage: Bool = false
    @State private var message: String = ""
    @State private var messageColor: Color = .black
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                if bluetoothManager.isConnected {
                    Text("Enter your corresponding WiFi information below")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding()
                    HStack {
                        TextField("Enter WiFi Name", text: $wifiSSID)
                            .padding() // Adds padding to the top and bottom of the secure field
                            .background(Color.secondary.opacity(0.25)) // Set background color and opacity
                            .cornerRadius(15)
                            .keyboardType(.default)
                    }
                    .padding(.horizontal, 20)
                    
                    HStack {
                        SecureField("Enter WiFi Password", text: $wifiPassword)
                            .padding() // Adds padding to the top and bottom of the secure field
                            .background(Color.secondary.opacity(0.25)) // Set background color and opacity
                            .cornerRadius(15)
                            .keyboardType(.default)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom,20)

                    if isLoading {
                        Text("Loading...")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        Button(action: submitCredentials) {
                            Text("Submit")
                                .padding()
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
                    
                    Text("Make sure to stay in range of the device")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Spacer()
                    Text("Connecting with Bluetooth...")
                        .padding()
                        .foregroundColor(.secondary)
                    ProgressView()
                    if countdownTimer.counter > 0 {
                        Text("\(countdownTimer.counter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack{
                            Text("Still not connecting?")
                                .font(.title2)
                                .bold()
                                .padding(.top)
                                .foregroundColor(.primary)
                            Text("Try powering off the counter and turning it back on again, in addition to restarting the app.")
                                .foregroundColor(.secondary)
                                .padding()
                                .multilineTextAlignment(.center)
                        }
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(25)
                        .padding(.horizontal)
                        .padding()
                    }
                    Spacer()
                    Text("Please turn on your Bluetooth")
                        .foregroundColor(.primary)
                        .bold()
                    Text("and ensure that the device is on and in range")
                        .foregroundColor(.primary)
                        .bold()
                        .padding(.bottom, 20)
                }
            }
            .padding()
            .navigationBarTitle("Bluetooth Setup", displayMode: .inline)
        }
        .onAppear {
            if !bluetoothManager.userId.isEmpty {
                bluetoothManager.initializeCentralManager()
            }
            countdownTimer.resetTimer()
        }
        .onChange(of: bluetoothManager.isConnected) {
            if bluetoothManager.isConnected {
                countdownTimer.timer?.invalidate()
            } else {
                countdownTimer.resetTimer()
            }
        }
    }

    func submitCredentials() {
        isLoading = true
        showMessage = false
        bluetoothManager.sendWiFiCredentials(ssid: wifiSSID, password: wifiPassword)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            isLoading = false
            checkDeviceStatus()
        }
    }

    func checkDeviceStatus() {
        let urlString = "\(bluetoothManager.serverURL)/api/connection_status?user_id=\(bluetoothManager.userId)"
        guard let url = URL(string: urlString) else {
            self.message = "Server end issue, please try again later."
            self.messageColor = .red
            self.showMessage = true
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.message = "Network error: \(error.localizedDescription)"
                    self.messageColor = .red
                    self.showMessage = true
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let data = data {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                               let status = json["status"] as? String {
                                if status == "online" {
                                    self.message = "Success!"
                                    self.messageColor = .green
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        self.presentationMode.wrappedValue.dismiss()
                                    }
                                } else {
                                    self.message = "WiFi name or password incorrect. Please try again."
                                    self.messageColor = .red
                                }
                                self.showMessage = true
                            } else {
                                print("Invalid JSON format")
                            }
                        } catch {
                            print("Failed to parse JSON: \(error.localizedDescription)")
                        }
                    } else {
                        print("No data received in response")
                    }
                } else {
                    self.message = "Server error. Please wait and try again."
                    self.messageColor = .red
                    self.showMessage = true
                }
            }
        }.resume()
    }
}
