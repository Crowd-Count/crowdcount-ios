import SwiftUI

struct SettingsView: View {
    @Binding var showSettings: Bool
    let device: Device
    let logOut: (String) -> Void

    @State private var isServerRunning: Bool = true
    @State private var showDirectionFlipAlert: Bool = false
    @State private var showDirectionConfirmAlert: Bool = false
    @State private var directionFlipped: Bool = false
    @State private var isLoadingDirection: Bool = true
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @EnvironmentObject var appSettings: AppSettings

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    private let apiService = APIService.shared

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
                    Text("they will only affect device \(device.deviceId)")
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    // Flip Counting Direction
                    HStack {
                        Button(action: {
                            showDirectionConfirmAlert = true
                        }) {
                            Text("Flip Counting Direction")
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

                    // Remove Device
                    HStack {
                        Button(action: {
                            logOut(device.deviceId)
                            presentationMode.wrappedValue.dismiss()
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

                    // Dark/Light mode toggle
                    HStack {
                        Text(appSettings.isDarkMode ? "Change to light mode  -" : "Change to dark mode  -")
                            .foregroundColor(.primary)
                        Image(systemName: appSettings.isDarkMode ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(.primary)
                    }
                    .onTapGesture {
                        withAnimation {
                            appSettings.isDarkMode.toggle()
                        }
                    }
                    .padding(.bottom, 10)

                    Text("Need some help?")
                        .foregroundColor(.secondary)
                    Link("info@crowdcount.tech", destination: URL(string: "mailto:info@crowdcount.tech")!)
                        .foregroundColor(.blue)
                }
            }
            .navigationTitle("Settings - \(device.deviceId)")
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Done")
                    .foregroundColor(.blue)
                    .bold()
            })
            .onAppear {
                checkServerStatus()
                fetchDirectionFlipped()
            }
            .alert("Direction Flipped", isPresented: $showDirectionFlipAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(directionFlipped ?
                        "Entry/Exit direction has been flipped. What was previously entry is now exit, and vice versa." :
                        "Entry/Exit direction has been reset to normal.")
                    Text("Note: It may take up to a minute for this change to take effect.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }
            .alert("Flip Counting Direction?", isPresented: $showDirectionConfirmAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    flipDirection()
                }
            } message: {
                Text("Flipping the entry and exit direction may take up to a minute to take effect.")
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    // MARK: - Server Calls

    private func checkServerStatus() {
        Task {
            let running = await apiService.checkServerStatus()
            await MainActor.run {
                isServerRunning = running
            }
        }
    }

    private func fetchDirectionFlipped() {
        Task {
            do {
                let flipped = try await apiService.getDirectionFlipped(
                    deviceId: device.deviceId,
                    password: device.password
                )
                await MainActor.run {
                    directionFlipped = flipped
                    isLoadingDirection = false
                }
            } catch {
                print("Error fetching direction flip: \(error)")
                await MainActor.run {
                    isLoadingDirection = false
                }
            }
        }
    }

    private func flipDirection() {
        let newValue = !directionFlipped

        Task {
            do {
                try await apiService.setDirectionFlipped(
                    deviceId: device.deviceId,
                    password: device.password,
                    flipped: newValue
                )
                await MainActor.run {
                    directionFlipped = newValue
                    showDirectionFlipAlert = true
                }
            } catch {
                print("Error updating direction flip: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to update direction flip"
                }
            }
        }
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
