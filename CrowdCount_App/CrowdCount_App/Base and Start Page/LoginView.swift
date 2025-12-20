import SwiftUI

struct LoginView: View {
    @Binding var userId: String
    @Binding var password: String
    @Binding var errorMessage: String?
    let setUser: () -> Void
    let serverStatus: String
    let serverStatusColor: Color
    @State private var isWiggling = false
    @State private var isTapped = true
    @State private var showingAddCounter = false
    @State private var tapCount = 0
    @State private var currentColorIndex = 0
    @State private var timer: Timer?
    @State private var animateColor = false
    @State private var isAnimating = false
    @State private var continuousTapping = false
    
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    
    let rainbowColors: [Color] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]
    
    var body: some View {
        VStack {
            Spacer()
            if #available(iOS 18.0, *) {
                Image(systemName: "hand.wave.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(animateColor ? rainbowColors[currentColorIndex % rainbowColors.count] : .primary)
                    .symbolEffect(.wiggle.byLayer, options: .speed(5) ,value: isTapped)
                    .animation(animateColor ? .easeInOut(duration: 0.3) : .none, value: currentColorIndex)
                    .onTapGesture {
                        if timer == nil {
                            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
                                tapCount = 0
                                animateColor = false
                                continuousTapping = false
                                timer?.invalidate()
                                timer = nil
                            }
                        } else {
                            timer?.invalidate()
                            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
                                tapCount = 0
                                animateColor = false
                                continuousTapping = false
                                timer?.invalidate()
                                timer = nil
                            }
                        }
                        tapCount += 1
                        if tapCount == 10 {
                            startRainbowAnimation()
                            tapCount = 0
                        }
                        isTapped.toggle()
                    }
                    .sensoryFeedback(
                        .impact(weight: .heavy, intensity: 0.9),
                        trigger: isTapped
                    )
                Text("Tap me!")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(5)
                    .italic()
            } else {
                Image(systemName: "hand.wave.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.primary)
            }
            Text("Welcome!")
                .bold()
                .font(.system(size: 50))
                .foregroundColor(.primary)
                .padding(5)
            
            if showingAddCounter {
                Text("Please add your device or purchase one at \(Text("[crowdcount.tech/products](https://www.crowdcount.tech/products)"))")
                    .foregroundColor(.secondary)
                    .padding(.bottom,10)
                    .multilineTextAlignment(.center)
            } else {
                Text("View our map or add a counter")
                    .foregroundColor(.secondary)
                    .padding(.bottom,10)
            }
            
            if let errorMessage = errorMessage, errorMessage != "Device already added" {
                Text(errorMessage)
                .foregroundColor(.red)
                .padding()
            }

            if showingAddCounter {
                HStack {
                    TextField("Enter Device ID", text: $userId)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                }
                .padding(.horizontal, 20)

                HStack {
                    SecureField("Enter Password", text: $password)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                HStack {
                    Button(action: {
                        showingAddCounter = false
                    }) {
                        Text("Cancel")
                            .padding()
                            .background(Color.secondary.opacity(0.75))
                            .foregroundColor(.primary)
                            .cornerRadius(20)
                    }
                    Button(action: setUser) {
                        Text("Add Device")
                            .padding()
                            .background(Color.blue.opacity(0.75))
                            .foregroundColor(.primary)
                            .cornerRadius(20)
                    }
                }
            } else {
                NavigationLink(destination: MapContentView()) {
                    if #available(iOS 26.0, *) {
                        HStack {
                            Image(systemName: "map")
                            Text("View the Map")
                        }
                        .padding()
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .font(.title2)
                        .background(Color.green.opacity(0.75))
                        .clipShape(Capsule())
                        .glassEffect()
                    } else {
                        HStack {
                            Image(systemName: "map")
                            Text("View the Map")
                        }
                        .padding()
                        .foregroundColor(.primary)
                        .font(.title2)
                        .background(Color.green.opacity(0.75))
                        .cornerRadius(22.5)
                    }
                }
                .padding(.top, 10)
                
                HStack{
                    Button(action: {
                        showingAddCounter = true
                    }) {
                        HStack {
                            Image(systemName: "plus.rectangle")
                            Text("Add a Counter")
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.75))
                        .foregroundColor(.primary)
                        .clipShape(
                            .rect(
                                topLeadingRadius: 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )
                    }
                    .padding(.top, 20)
                    
                    Button(action: {
                        userId = "Demo"
                        password = "password"
                        setUser()
                    }) {
                        HStack {
                            Image(systemName: "sparkle")
                            Text("Demo")
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.75))
                        .foregroundColor(.primary)
                        .clipShape(
                            .rect(
                                topLeadingRadius: 10,
                                bottomLeadingRadius: 10,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: 20
                            )
                        )
                    }
                    .padding(.top, 20)
                }
            }
            
            Spacer()
        }
        .padding()
        .padding(.bottom,20)
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
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
        .navigationBarItems(trailing: Button(action: {
            toggleMode()
        }) {
            Image(systemName: appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding()
        })
    }
    
    func toggleMode() {
        withAnimation {
            appSettings.isDarkMode.toggle()
        }
    }
    
    private func startRainbowAnimation() {
        animateColor = true
        isAnimating = true
        continuousTapping = true
        let animationDuration = 2.0 / Double(rainbowColors.count)

        for i in 0..<rainbowColors.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * Double(i)) {
                currentColorIndex = i
                if i == rainbowColors.count - 1 {
                    if continuousTapping {
                        startRainbowAnimation()
                    } else {
                        animateColor = false
                        currentColorIndex = 0
                        isAnimating = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Login View") {
    NavigationView {
        LoginView(
            userId: .constant(""),
            password: .constant(""),
            errorMessage: .constant(nil),
            setUser: {},
            serverStatus: "Online",
            serverStatusColor: .green
        )
        .environmentObject(AppSettings())
    }
}

#Preview("Login View - With Error") {
    NavigationView {
        LoginView(
            userId: .constant("T1234"),
            password: .constant("password"),
            errorMessage: .constant("Invalid credentials"),
            setUser: {},
            serverStatus: "Online",
            serverStatusColor: .green
        )
        .environmentObject(AppSettings())
    }
}
