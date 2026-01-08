import SwiftUI

struct AddUserPage: View {
    @Binding var users: [User]
    @Binding var totalCount: Int
    @Binding var userPasswords: [UUID: String]
    @State private var userId: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) var colorScheme

    let serverURL: String
    let startDeviceStatusCheck: (User) -> Void
    let startLiveCountUpdate: () -> Void  // Added this to trigger the count update

    // Location support - closure-based approach for correct location assignment
    let onDeviceAdded: (String) -> Void  // Called with deviceId after successful add
    let isInLocationView: Bool  // For UI text customization
    var isLocationOnMap: Bool = false  // Whether the current location is on the public map
    var locationHasCounters: Bool = false  // Whether the location already has counters
    var locationName: String = ""  // Name of the current location
    var onDeleteLocation: (() -> Void)? = nil  // Called when user wants to delete empty location
    @ObservedObject var alertViewModel: AlertViewModel

    @State private var showDeleteConfirmation: Bool = false

    @FocusState private var focusedField: Field?

    enum Field {
        case userId, password
    }

    var body: some View {
        VStack {
            Image(systemName: "plus.bubble")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40) // Adjust the width and height as needed
                .foregroundColor(.secondary)

            if isInLocationView {
                Text("Add a counter to \(locationName)")
                    .foregroundColor(.primary)
                    .padding()
                    .multilineTextAlignment(.center)
            } else {
                (Text("Have ")
                    .foregroundColor(.secondary) +
                 Text("multiple counters?")
                    .foregroundColor(.primary) +
                 Text("\nAdd them here!")
                    .foregroundColor(.secondary))
                    .padding()
                    .multilineTextAlignment(.center)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.bottom)
            }

            HStack {
                TextField("Enter Device ID", text: $userId, onEditingChanged: { _ in clearErrorMessage() })
                    .padding()
                    .background(Color.secondary.opacity(0.25))
                    .cornerRadius(15)
                    .focused($focusedField, equals: .userId)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 20)

            HStack {
                SecureField("Enter Password", text: $password, onCommit: clearErrorMessage)
                    .padding()
                    .background(Color.secondary.opacity(0.25))
                    .cornerRadius(15)
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            Button(action: addUser) {
                Text("Add Device")
                    .padding()
                    .background(Color.secondary.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
            }

            if isInLocationView {
                Group {
                    if !locationHasCounters {
                        // Empty location - welcoming message
                        Text("Add your first counter to get started.")
                    } else if isLocationOnMap {
                        // Map location with existing counters
                        Text("Only counters belonging to '\(locationName)' on the public map can be added here. Other counters will be placed in a new location.")
                    } else {
                        // Local location with existing counters
                        Text("Add another counter to this location.")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Delete Location button - only show for empty locations
                if !locationHasCounters, onDeleteLocation != nil {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Location")
                        }
                        .padding()
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(20)
                    }
                    .padding(.top, 30)
                }
            }
        }
        .padding()
        .alert("Delete Location?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDeleteLocation?()
            }
        } message: {
            Text("Are you sure you want to delete '\(locationName)'? This cannot be undone.")
        }
    }

    func addUser() {
        guard !userId.isEmpty else {
            errorMessage = "Please enter a Device ID"
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Please enter a Password"
            return
        }

        checkPassword(userId: userId, password: password) { success in
            DispatchQueue.main.async {
                if success {
                    if !users.contains(where: { $0.userId == userId }) {
                        // Save deviceId before clearing fields
                        let deviceId = userId

                        let newUser = User(id: UUID(), userId: deviceId, currentCount: 0)
                        users.append(newUser)
                        userPasswords[newUser.id] = password // Save the password for the new user
                        calculateTotalCount()
                        clearFields()
                        saveUsers()
                        savePasswords() // Save the passwords

                        // Add device to location via closure (handles correct location assignment)
                        onDeviceAdded(deviceId)

                        startDeviceStatusCheck(newUser)
                        startLiveCountUpdate()  // Ensure count update starts for the new user
                        hideKeyboard()
                    } else {
                        errorMessage = "Device already added"
                        clearFields()
                    }
                } else {
                    errorMessage = "Incorrect Device ID or Password"
                    clearFields()
                }
            }
        }
    }

    func calculateTotalCount() {
        totalCount = users.reduce(0) { $0 + $1.currentCount }
    }
    
    func clearFields() {
        userId = ""
        password = ""
    }
    
    func saveUsers() {
        if let encoded = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encoded, forKey: "users")
        }
    }

    func savePasswords() {
        if let encoded = try? JSONEncoder().encode(userPasswords) {
            UserDefaults.standard.set(encoded, forKey: "userPasswords")
        }
    }
    
    func clearErrorMessage() {
        errorMessage = nil
    }

    func hideKeyboard() {
        focusedField = nil
    }
    
    func checkPassword(userId: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverURL)/check_password") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data,
               let response = try? JSONDecoder().decode(PasswordCheckResponse.self, from: data) {
                completion(response.isPasswordCorrect)
            } else {
                completion(false)
            }
        }.resume()
    }
}

struct PasswordCheckResponse: Decodable {
    let isPasswordCorrect: Bool

    enum CodingKeys: String, CodingKey {
        case isPasswordCorrect = "is_password_correct"
    }
}
