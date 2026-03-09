import SwiftUI

struct CounterEntry: Identifiable {
    let id: UUID
    var deviceId: String
    var password: String

    init(id: UUID = UUID(), deviceId: String = "", password: String = "") {
        self.id = id
        self.deviceId = deviceId
        self.password = password
    }
}

struct LoginView: View {
    @Binding var userId: String
    @Binding var password: String
    @Binding var locationName: String
    @Binding var errorMessage: String?
    @Binding var isLoggingIn: Bool
    @Binding var additionalCounters: [CounterEntry]
    let setUser: () -> Void
    let serverStatus: String
    let serverStatusColor: Color
    @ObservedObject var alertViewModel: AlertViewModel
    @State private var isWiggling = false
    @State private var isTapped = true
    @State private var showingAddCounter = false
    @State private var tapCount = 0
    @State private var currentColorIndex = 0
    @State private var timer: Timer?
    @State private var animateColor = false
    @State private var isAnimating = false
    @State private var continuousTapping = false
    @State private var mapButtonTapped = false
    @State private var counterEntries: [CounterEntry] = [CounterEntry()]
    @State private var agreedToTerms = false

    // Typewriter animation
    @State private var welcomeText = ""
    @State private var hasAnimatedWelcome = false
    private let fullWelcomeText = "Welcome!"

    @StateObject private var loginTextViewModel = LoginTextViewModel()
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    let rainbowColors: [Color] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]

    var body: some View {
        VStack {
            if !showingAddCounter || counterEntries.count <= 1 {
                Spacer()
            }

            if !showingAddCounter {
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
                    Text(loginTextViewModel.loginText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(5)
                        .italic()
                        .onAppear {
                            loginTextViewModel.fetchLoginText()
                        }
                } else {
                    Image(systemName: "hand.wave.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.primary)
                    Text(loginTextViewModel.loginText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(5)
                        .italic()
                        .onAppear {
                            loginTextViewModel.fetchLoginText()
                        }
                }
            }
            Text(welcomeText)
                .bold()
                .font(.system(size: 50))
                .foregroundColor(.primary)
                .padding(5)
                .onAppear {
                    if !hasAnimatedWelcome {
                        animateWelcomeText()
                    }
                }

            if showingAddCounter {
                Text("Please add your device or purchase one at \(Text("[crowdcount.tech/products](https://www.crowdcount.tech/products)"))")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                    .multilineTextAlignment(.center)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            } else {
                Text("View our map or add a counter")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
            
            if let errorMessage = errorMessage, errorMessage != "Device already added" {
                Text(errorMessage)
                .foregroundColor(.red)
                .padding()
            }

            if showingAddCounter {
                if counterEntries.count > 1 {
                    ScrollView {
                        VStack {
                            counterFormContent
                        }
                    }
                } else {
                    counterFormContent
                }
            } else {
                VStack(spacing: 20) {
                    NavigationLink(destination: MapContentView()) {
                        if #available(iOS 26.0, *) {
                            HStack {
                                Image(systemName: "map")
                                Text("View All Locations")
                            }
                            .frame(width: 200)
                            .padding()
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                            .font(.title3)
                            .background(Color.green.opacity(0.75))
                            .clipShape(Capsule())
                            .glassEffect(.regular.interactive())
                        } else {
                            HStack {
                                Image(systemName: "map")
                                Text("View All Locations")
                            }
                            .frame(width: 200)
                            .padding()
                            .foregroundColor(.primary)
                            .font(.title3)
                            .background(Color.green.opacity(0.75))
                            .clipShape(Capsule())
                        }
                    }

                    NavigationLink(destination: MapContentView(initialColorFilter: ["orange"])) {
                        if #available(iOS 26.0, *) {
                            HStack {
                                Image(systemName: "fork.knife")
                                Text("Bars & Restaurants")
                            }
                            .frame(width: 200)
                            .padding()
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                            .font(.title3)
                            .background(Color.orange.opacity(0.75))
                            .clipShape(Capsule())
                            .glassEffect(.regular.interactive())
                        } else {
                            HStack {
                                Image(systemName: "fork.knife")
                                Text("Bars & Restaurants")
                            }
                            .frame(width: 200)
                            .padding()
                            .foregroundColor(.primary)
                            .font(.title3)
                            .background(Color.orange.opacity(0.75))
                            .clipShape(Capsule())
                        }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    mapButtonTapped.toggle()
                })
                .sensoryFeedback(.impact(weight: .light), trigger: mapButtonTapped)
                .padding(.top, 10)
                .padding(.bottom, 0)

                HStack{
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingAddCounter = true
                        }
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
                                bottomTrailingRadius: 20,
                                topTrailingRadius: 20
                            )
                        )
                    }
                    .padding(.top, 20)
                }
                .transition(.opacity)

//          REMOVED DEMO MODE FOR NOW, TOO ANNOYING TO KEEP IMPLEMENTING IT AND DONT THINK MANY PEOPLE WILL USE IT, can reimplement another time
//                    Button(action: {
//                        userId = "Demo"
//                        password = "password"
//                        setUser()
//                    }) {
//                        HStack {
//                            Image(systemName: "sparkle")
//                            Text("Demo")
//                        }
//                        .padding()
//                        .background(Color.secondary.opacity(0.75))
//                        .foregroundColor(.primary)
//                        .clipShape(
//                            .rect(
//                                topLeadingRadius: 10,
//                                bottomLeadingRadius: 10,
//                                bottomTrailingRadius: 20,
//                                topTrailingRadius: 20
//                            )
//                        )
//                    }
//                    .padding(.top, 20)
            }

            if !showingAddCounter || counterEntries.count <= 1 {
                Spacer()
            }
        }
        .padding()
        .padding(.bottom, 20)
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 14) {
                    NavigationLink(destination: InformationView()) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "info")
                                .foregroundColor(colorScheme == .dark ? .white : .primary)
                        } else {
                            Image(systemName: "info.circle")
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.leading, alertViewModel.alertExists ? 8 : 0)
                    if alertViewModel.alertExists {
                        Button(action: {
                            alertViewModel.showAlert = true
                        }) {
                            if #available(iOS 26.0, *) {
                                Image(systemName: "bell.badge.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.red, .primary)
                            } else {
                                Image(systemName: "bell.badge.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    toggleMode()
                }) {
                    Image(systemName: appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var counterFormContent: some View {
        HStack {
            TextField("Enter Location Name", text: $locationName)
                .padding()
                .background(Color.secondary.opacity(0.25))
                .cornerRadius(15)
                .textContentType(.location)
        }
        .padding(.horizontal, 20)

        ForEach($counterEntries) { $entry in
            VStack(spacing: 8) {
                if counterEntries.count > 1 {
                    HStack {
                        Text("Counter \((counterEntries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if counterEntries.first?.id != entry.id {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    counterEntries.removeAll { $0.id == entry.id }
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Enter Device ID", text: $entry.deviceId)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Case sensitive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Enter Password", text: $entry.password)
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)
                        .textContentType(.password)
                    Text("Case sensitive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 20)
            }
        }

        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                counterEntries.append(CounterEntry())
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.subheadline)
                Text("Add Another Counter")
                    .font(.subheadline)
            }
            .foregroundColor(.blue)
        }
        .padding(.top, 4)
        .padding(.bottom, 20)

        HStack(spacing: 8) {
            Button(action: { agreedToTerms.toggle() }) {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .foregroundColor(agreedToTerms ? .blue : .secondary)
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("I agree to the \(Text("[Terms of Use](https://www.crowdcount.tech/legal/terms-of-use)")) and \(Text("[Privacy Policy](https://www.crowdcount.tech/legal/privacy-policy)"))")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .onTapGesture {
                    agreedToTerms.toggle()
                }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)

        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingAddCounter = false
                    errorMessage = nil
                    userId = ""
                    password = ""
                    locationName = ""
                    counterEntries = [CounterEntry()]
                    agreedToTerms = false
                }
            }) {
                Text("Cancel")
                    .padding()
                    .background(Color.secondary.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
            }
            Button(action: {
                if let first = counterEntries.first {
                    userId = first.deviceId
                    password = first.password
                }
                additionalCounters = counterEntries.dropFirst().filter {
                    !$0.deviceId.isEmpty && !$0.password.isEmpty
                }
                setUser()
            }) {
                if isLoggingIn {
                    ProgressView()
                        .padding()
                        .frame(width: 140)
                        .background(Color.blue.opacity(0.4))
                        .cornerRadius(20)
                } else {
                    Text(counterEntries.count > 1 ? "Add Devices" : "Add Device")
                        .padding()
                        .background(Color.blue.opacity(0.75))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                }
            }
            .disabled(isLoggingIn || !agreedToTerms)
            .opacity(!agreedToTerms ? 0.5 : 1.0)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }

    func toggleMode() {
        withAnimation {
            appSettings.isDarkMode.toggle()
        }
    }

    private func animateWelcomeText() {
        welcomeText = ""
        hasAnimatedWelcome = true

        for (index, character) in fullWelcomeText.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                welcomeText += String(character)
            }
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
            locationName: .constant(""),
            errorMessage: .constant(nil),
            isLoggingIn: .constant(false),
            additionalCounters: .constant([]),
            setUser: {},
            serverStatus: "Online",
            serverStatusColor: .green,
            alertViewModel: AlertViewModel()
        )
        .environmentObject(AppSettings())
    }
}

#Preview("Login View - With Error") {
    NavigationView {
        LoginView(
            userId: .constant("T1234"),
            password: .constant("password"),
            locationName: .constant("My Location"),
            errorMessage: .constant("Invalid credentials"),
            isLoggingIn: .constant(false),
            additionalCounters: .constant([]),
            setUser: {},
            serverStatus: "Online",
            serverStatusColor: .green,
            alertViewModel: AlertViewModel()
        )
        .environmentObject(AppSettings())
    }
}
