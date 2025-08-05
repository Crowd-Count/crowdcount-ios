import SwiftUI

struct AddUserPage: View {
    @Binding var users: [User]
    @Binding var totalCount: Int
    @Binding var userPasswords: [UUID: String]
    @State private var userId: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    
    @EnvironmentObject var appSettings: AppSettings

    let serverURL: String
    let startDeviceStatusCheck: (User) -> Void
    let startLiveCountUpdate: () -> Void  // Added this to trigger the count update

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
            (Text("Have ")
                .foregroundColor(.secondary) +
             Text("multiple counters?")
                .foregroundColor(.primary) +
             Text("\nAdd them here!")
                .foregroundColor(.secondary))
                .padding()
                .multilineTextAlignment(.center)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.bottom)
            }

            HStack {
                TextField("Enter Device ID", text: $userId, onEditingChanged: { _ in clearErrorMessage() })
                    .padding() // Adds padding to the top and bottom of the text field
                    .background(Color.secondary.opacity(0.25)) // Set background color and opacity
                    .cornerRadius(15)
                    .focused($focusedField, equals: .userId)
            }
            .padding(.horizontal, 20) // Adds padding to the left and right of the box itself
            
            HStack {
                SecureField("Enter Password", text: $password, onCommit: clearErrorMessage)
                    .padding() // Adds padding to the top and bottom of the secure field
                    .background(Color.secondary.opacity(0.25)) // Set background color and opacity
                    .cornerRadius(15)
                    .focused($focusedField, equals: .password)
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
        }
        .padding()
        .navigationBarItems(leading: NavigationLink(destination: InformationView()) {
            Image(systemName: "info.circle")
                .foregroundColor(.primary)
                .padding()
        })
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
                        let newUser = User(id: UUID(), userId: userId, currentCount: 0)
                        users.append(newUser)
                        userPasswords[newUser.id] = password // Save the password for the new user
                        calculateTotalCount()
                        clearFields()
                        saveUsers()
                        savePasswords() // Save the passwords
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
        guard let url = URL(string: "\(serverURL)/api/check_password?user_id=\(userId)&password=\(password)") else {
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
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
