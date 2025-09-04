import SwiftUI

struct SettingsView: View {
    @Binding var showSettings: Bool
    var user: User
    @Binding var updateFrequencies: [UUID: Double]
    let logOut: (UUID) -> Void
    @State private var isServerRunning: Bool = true
    
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showPasswordFields: Bool = false
    @State private var showSlider: Bool = false
    
    @State private var showAlert: Bool = false
    @State private var showConfirmationAlert: Bool = false
    @State private var showDemoAlert: Bool = false
    @State private var confirmationUserId: String = ""
    @State private var confirmationPassword: String = ""
    
    @EnvironmentObject var appSettings: AppSettings

    let serverURL: String

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            VStack {
                if !isServerRunning {
                    Text("Maintenance")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    Spacer()
                    Image(systemName: "exclamationmark.bubble")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.secondary)
                        .padding(5)
                    Text("These are ")
                        .bold()
                        .foregroundColor(.secondary)
                    + Text("device settings")
                        .bold()
                        .foregroundColor(.primary)
                    Text("they will only affect device \(user.userId)")
                        .foregroundColor(.secondary)
                        .padding(.bottom,10)
                    if !showPasswordFields {
                        if !showSlider {
                            Button(action: {
                                showSlider.toggle()
                            }) {
                                Text("Update Frequency")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(.primary)
                            }
                            .padding(10)
                        }
                        
                        if showSlider {
                            HStack {
                                Text("Update Frequency:")
                                    .bold()
                                    .foregroundColor(.secondary)
                                Text("\(Int(updateFrequencies[user.id, default: 1.0])) sec")
                                    .bold()
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            Slider(value: Binding(
                                get: {
                                    updateFrequencies[user.id] ?? 1.0
                                },
                                set: { newValue in
                                    let validValues: [Double] = [1, 3, 5, 10, 15, 30, 45, 60]
                                    updateFrequencies[user.id] = validValues.min(by: { abs($0 - newValue) < abs($1 - newValue) }) ?? newValue
                                }
                            ), in: 1...60, step: 1)
                                .accentColor(.blue)
                                .padding(.horizontal,40)
                            
                            Button(action: {
                                showSlider.toggle()
                            }) {
                                Text("Close")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(.primary)
                            }
                            .padding(10)
                        }
                    }
                    
                    if !showPasswordFields {
                        HStack {
                            Button(action: {
                                showPasswordFields.toggle()
                                errorMessage = nil
                                successMessage = nil
                            }) {
                                Text("Change Password")
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(10)
                    }
                    
                    if showPasswordFields {
                        VStack(spacing: 20) {
                            HStack{
                                SecureField("Enter Current Password", text: $currentPassword)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                            }
                            .padding(.horizontal, 20)
                            
                            HStack{
                                SecureField("Enter New Password", text: $newPassword)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                            }
                            .padding(.horizontal, 20)
                                
                            HStack{
                                SecureField("Confirm New Password", text: $confirmPassword)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                            }
                            .padding(.horizontal, 20)
                                
                            HStack {
                                Button(action: {
                                    showPasswordFields = false
                                    errorMessage = nil
                                    successMessage = nil
                                }) {
                                    Text("Cancel")
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(colorScheme == .dark ?
                                                    Color(UIColor.tertiarySystemBackground) :
                                                    Color(UIColor.secondarySystemBackground))
                                        )
                                        .foregroundColor(.primary)
                                }
                                Button(action: {
                                    changePassword()
                                }) {
                                    Text("Set New Password")
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.blue.opacity(0.8))
                                        )
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .padding()
                            }
                            
                            if let successMessage = successMessage {
                                Text(successMessage)
                                    .foregroundColor(.green)
                                    .padding()
                            }
                        }
                        .padding()
                        Spacer()
                    }
                    
                    if !showPasswordFields {
                        HStack {
                            Button(action: {
                                showAlert = true
                            }) {
                                Text("Reset Data")
                                    .padding()
                                    .bold()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.red.opacity(0.2))
                                    )
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(10)
                        HStack {
                            Button(action: {
                                logOut(user.id)
                                presentationMode.wrappedValue.dismiss()
                                print("Remove Device pressed. showSettings is now: \(showSettings)")
                            }) {
                                Text("Remove Device")
                                    .padding()
                                    .bold()
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(colorScheme == .dark ?
                                                Color(UIColor.tertiarySystemBackground).opacity(0.5) :
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(10)
                        Spacer()
                        HStack {
                            Text(appSettings.isDarkMode ? "Change to light mode  -" : "Change to dark mode  -")
                                .foregroundColor(.primary)
                            Image(systemName: appSettings.isDarkMode ? "sun.max.fill" : "moon.fill")
                                .foregroundColor(.primary)
                        }
                        .onTapGesture {
                            toggleMode()
                        }
                        .padding(.bottom,10)
                        Text("Need some help?")
                            .foregroundColor(.secondary)
                        Link("help@crowdcount.tech", destination: URL(string: "mailto:help@crowdcount.tech")!)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Settings - \(user.userId)")
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
                print("Done pressed. showSettings is now: \(showSettings)")
            }) {
                Text("Done")
                    .foregroundColor(.blue)
                    .bold()
            })
            .onAppear {
                // Check the server status when the view appears
                checkServerStatus()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Are you sure?"),
                    message: Text("Resetting a device's data is irreversible, all your history and data for this device will be lost."),
                    primaryButton: .destructive(Text("I am sure")) {
                        if user.userId == "Demo"{
                            showDemoAlert = true
                        }
                        else {
                            showConfirmationAlert = true
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Sorry, but you can't reset the demo data", isPresented: $showDemoAlert) {
                Button("Ah geeze...", role: .cancel) {}
            } message: {
                Text("Good try though")
            }
            .alert("Confirm Device ID and password", isPresented: $showConfirmationAlert) {
                TextField("\(user.userId)", text: $confirmationUserId)
                    .foregroundColor(.primary)
                SecureField("Password", text: $confirmationPassword)
                    .foregroundColor(.primary)
                Button("Cancel", role: .cancel) {}
                Button("Confirm") {
                    resetDeviceData()
                }
            } message: {
                Text("Please enter your Device ID to confirm:")
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }
    
    func toggleMode() {
        withAnimation {
            appSettings.isDarkMode.toggle()
        }
    }

    func changePassword() {
        guard !currentPassword.isEmpty else {
            errorMessage = "Please enter the current password"
            return
        }
        
        guard !newPassword.isEmpty else {
            errorMessage = "Please enter a new password"
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match"
            return
        }
        
        let urlString = "\(serverURL)/set_password"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let bodyData = "user_id=\(user.userId)&current_password=\(currentPassword)&new_password=\(newPassword)"
        request.httpBody = bodyData.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error changing password: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("No response from server")
                DispatchQueue.main.async {
                    self.errorMessage = "No response from server"
                }
                return
            }
            
            print("Received response: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.successMessage = "Password changed successfully"
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to change password"
                }
            }
        }.resume()
    }

    func resetDeviceData() {
        guard confirmationUserId == user.userId else {
            errorMessage = "Device ID does not match"
            return
        }
        
        let urlString = "\(serverURL)/reset_device_data?user_id=\(user.userId)&password=\(confirmationPassword)"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error resetting data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("No response from server")
                DispatchQueue.main.async {
                    self.errorMessage = "No response from server"
                }
                return
            }
            
            print("Received response: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.successMessage = "Device data reset successfully"
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to reset device data"
                }
            }
        }.resume()
    }

    func checkServerStatus() {
        let urlString = "\(serverURL)/healthcheck"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isServerRunning = false
            }
            return
        }

        URLSession.shared.dataTask(with: url) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.isServerRunning = true
                } else {
                    self.isServerRunning = false
                }
            }
        }.resume()
    }
}

// Extension to handle keyboard avoidance
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Extension for adaptive keyboard
struct KeyboardAdaptive: ViewModifier {
    @State private var currentHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .padding(.bottom, currentHeight)
                .onAppear {
                    let safeAreaInsetsBottom = geometry.safeAreaInsets.bottom
                    
                    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                            let keyboardHeight = keyboardFrame.height
                            DispatchQueue.main.async {
                                currentHeight = keyboardHeight - safeAreaInsetsBottom
                            }
                        }
                    }
                    
                    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                        DispatchQueue.main.async {
                            currentHeight = 0
                        }
                    }
                }
                .onDisappear {
                    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
                    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
                }
        }
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        self.modifier(KeyboardAdaptive())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(showSettings: .constant(true), user: User(id: UUID(), userId: "SampleUser", currentCount: 0), updateFrequencies: .constant([:]), logOut: { _ in }, serverURL: "\(AppSettings.apiBaseURL)")
            .environmentObject(AppSettings())
    }
}
