import SwiftUI

struct UserView: View {
    @Binding var user: User
    let serverURL: String
    @Binding var userPasswords: [UUID: String]
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showNewCountField: Bool = false
    @State private var showOvercrowdingField: Bool = false
    
    @State private var newCount: String = ""
    @State private var newOvercrowdingCount: String = ""
    
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
    @State private var temporaryCount: String? = nil
    
    @State private var isOvercrowdingEnabled: Bool = false
    @State private var overcrowdingLimit: String? = nil
    
    @EnvironmentObject var appSettings: AppSettings
    
    @State private var showDemoAlert: Bool = false // Added state variable for alert
    
    var body: some View {
        VStack {
            if user.userId == "Demo"{
                Spacer()
                Text("")
                    .padding(.top, 40)
            }
            if user.userId == "T0000" || !isBluetoothSetupRequired {
                Image(systemName: "wifi")
                    .foregroundColor(.green)
                    .font(.system(size: 25))
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
                    .font(.system(size: 25))
                    .symbolRenderingMode(.hierarchical)
            }
            
            Text((user.userId == "T0000" || !isBluetoothSetupRequired) ? "Live Count for:" : "Last Count for:")
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
            
            HStack {
                Text(temporaryCount ?? "\(user.currentCount)")
                    .font(.system(size: 50))
                    .fontWeight(.bold)
                if isOvercrowdingEnabled, let limit = overcrowdingLimit {
                    Text("/ \(limit)")
                        .font(.system(size: 50))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
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
                    showOvercrowdingField = false
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
            
            HStack {
                Button(action: {
                    showOvercrowdingField.toggle()
                    showNewCountField = false
                }) {
                    HStack {
                        if !showOvercrowdingField {
                            Image(systemName: "exclamationmark.shield")
                                .foregroundColor(.primary)
                        }
                        Text(showOvercrowdingField ? "Cancel" : "Overcrowding Limit")
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(showOvercrowdingField ? 0.25 : 0.5))
                    .cornerRadius(20)
                }
                
                if showOvercrowdingField {
                    Button(action: {
                        if user.userId == "Demo" {
                            showDemoAlert = true // Show alert for demo user
                            showOvercrowdingField.toggle()
                            newOvercrowdingCount = ""
                        } else {
                            setOvercrowding(user, newOvercrowdingCount)
                            showOvercrowdingField.toggle()
                            newOvercrowdingCount = ""
                        }
                    }) {
                        Text("Submit")
                            .padding()
                            .background(Color.secondary.opacity(0.75))
                            .foregroundColor(.primary)
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.top, 10)
            .alert(isPresented: $showDemoAlert) { // Alert modifier
                Alert(
                    title: Text("Demo Mode"),
                    message: Text("Sorry, but you can't change the overcrowding limit in demo mode."),
                    dismissButton: .default(Text("Ah gee willikers!"))
                )
            }
            
            if showOvercrowdingField {
                HStack {
                    TextField("Enter Overcrowding Limit", text: $newOvercrowdingCount)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                        .keyboardType(.numberPad)
                }
                .padding(.horizontal, 20)
            }
            
            NavigationLink(destination: HistoricView(userId: user.userId, userUUID: user.id, userPasswords: $userPasswords)) {
                HStack {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Text("Count History")
                }
                .padding()
                .background(Color.blue.opacity(0.75))
                .foregroundColor(.primary)
                .cornerRadius(20)
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
            
            if isBluetoothSetupRequired && user.userId != "T0000" {
                NavigationLink(destination: BluetoothSetupView(
                    wifiSSID: $wifiSSID,
                    wifiPassword: $wifiPassword,
                    bluetoothManager: bluetoothManager,
                    sendWiFiCredentials: sendWiFiCredentials
                )) {
                    Text("Reconnect Device to WiFi")
                        .padding()
                        .background(Color.red.opacity(0.75))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    bluetoothManager.userId = user.userId
                    bluetoothManager.fetchBluetoothUUIDs { success in
                        if !success {
                            deviceStatusMessage = "Failed to fetch Bluetooth UUIDs"
                        }
                    }
                })
                .padding(.top, 10)
            }
            
            if user.userId == "Demo"{
                Spacer()
                HStack {
                    Button(action: {
                        logOut(user.id)
                        print("Remove Device pressed.")
                    }) {
                        Text("Exit Demo")
                            .padding()
                            .bold()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .padding()
        .navigationBarItems(trailing: Button(action: showSettingsForUser) {
            Image(systemName: "gear")
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding()
        })
        .navigationBarItems(leading: NavigationLink(destination: InformationView()) {
            if #available(iOS 26.0, *) {
                Image(systemName: "info")
                    .padding()
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
            } else {
                Image(systemName: "info.circle")
                    .foregroundColor(.primary)
                    .padding()
            }
        })
        .onAppear {
            deviceName = loadDeviceName()
            checkIfOvercrowdingExists(user)
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
    
    // MARK: - API Overcrowding Functions
    
    func setOvercrowding(_ user: User, _ overcrowdingValue: String) {
        guard let password = userPasswords[user.id] else { return }
        
        if overcrowdingValue == "0" {
            removeOvercrowding(user)
            return
        }
        
        guard let url = URL(string: "\(serverURL)/add_overcrowding") else { return }
        
        let body: [String: Any] = [
            "device_name": user.userId,
            "overcrowding_value": overcrowdingValue,
            "password": password
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Failed to encode JSON: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let _ = data, error == nil else {
                print("Network error: \(String(describing: error))")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Overcrowding value submitted successfully")
                DispatchQueue.main.async {
                    self.isOvercrowdingEnabled = true
                    self.overcrowdingLimit = overcrowdingValue
                }
            } else {
                print("Failed to submit overcrowding value")
            }
        }.resume()
    }
    
    func fetchOvercrowdingLimit(_ user: User) {
        guard let url = URL(string: "\(serverURL)/get_overcrowding?device_name=\(user.userId)") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error: \(String(describing: error))")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let overcrowdingLimit = json["overcrowding"] as? Int {
                DispatchQueue.main.async {
                    self.overcrowdingLimit = String(overcrowdingLimit)
                    self.isOvercrowdingEnabled = true
                }
            } else {
                print("Failed to fetch overcrowding limit")
                DispatchQueue.main.async {
                    self.overcrowdingLimit = nil
                    self.isOvercrowdingEnabled = false
                }
            }
        }.resume()
    }
    
    func removeOvercrowding(_ user: User) {
        guard let password = userPasswords[user.id] else { return }
        guard let url = URL(string: "\(serverURL)/remove_overcrowding") else { return }
        
        let body: [String: Any] = [
            "device_name": user.userId,
            "password": password
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Failed to encode JSON: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let _ = data, error == nil else {
                print("Network error: \(String(describing: error))")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Overcrowding value removed successfully")
                DispatchQueue.main.async {
                    self.isOvercrowdingEnabled = false
                    self.overcrowdingLimit = nil
                }
            } else {
                print("Failed to remove overcrowding value")
            }
        }.resume()
    }
    
    func checkIfOvercrowdingExists(_ user: User) {
        guard let url = URL(string: "\(serverURL)/check_if_overcrowding_exists?device_name=\(user.userId)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error: \(String(describing: error))")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let overcrowdingExists = json["overcrowding_exists"] as? Bool {
                DispatchQueue.main.async {
                    self.isOvercrowdingEnabled = overcrowdingExists
                    if overcrowdingExists {
                        self.fetchOvercrowdingLimit(user)
                    } else {
                        self.overcrowdingLimit = nil
                    }
                }
            } else {
                print("Failed to check if overcrowding exists")
                DispatchQueue.main.async {
                    self.isOvercrowdingEnabled = false
                    self.overcrowdingLimit = nil
                }
            }
        }.resume()
    }
}

