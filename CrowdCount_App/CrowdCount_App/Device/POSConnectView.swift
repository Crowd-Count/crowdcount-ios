import SwiftUI
import AuthenticationServices

/// Two-step POS connection flow:
/// 1. Provider selection with direct "Sign in" action
/// 2. Location picker → Connect
struct POSConnectView: View {
    let locationId: String
    let locationName: String
    let credentials: [[String: String]]
    let signingDevice: (String, String)
    let onConnected: () -> Void

    @Environment(\.dismiss) var dismiss

    @State private var step: ConnectStep = .provider
    @State private var isLoading: Bool = false
    @State private var error: String?

    // POS account (from OAuth or existing)
    @State private var posAccountId: String = ""

    // Location picker
    @State private var posLocations: [POSStoreLocation] = []
    @State private var selectedPosLocationId: String?

    // Keep coordinator alive for the duration of the OAuth session
    @State private var webAuthCoordinator: WebAuthCoordinator?

    private let apiService = APIService.shared

    enum ConnectStep {
        case provider
        case locations
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .provider:
                        providerContent
                    case .locations:
                        locationsContent
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: step)
            }
            .navigationTitle(step == .provider ? "Connect POS" : "Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step == .locations {
                        Button {
                            withAnimation {
                                error = nil
                                step = .provider
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.medium)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Provider Selection (with direct Sign In)

    private var providerContent: some View {
        List {
            Section {
                // Square — Sign In directly
                Button {
                    handleSquareSignIn()
                } label: {
                    HStack(spacing: 14) {
                        Image("SquareLogo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with Square")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Connect your Square POS account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .disabled(isLoading)

                // Toast — Coming Soon
                HStack(spacing: 14) {
                    Image("ToastLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toast")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .opacity(0.4)
            } header: {
                Text("Connect a POS system to \(locationName) to see sales data alongside foot traffic.")
            }

            errorSection
        }
    }

    // MARK: - Step 2: Location Picker

    private var locationsContent: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading Square locations...")
                            .foregroundColor(.secondary)
                    }
                }
            } else if posLocations.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No locations found in your Square account.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section {
                    ForEach(posLocations) { loc in
                        Button {
                            selectedPosLocationId = loc.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    if let address = loc.address {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedPosLocationId == loc.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .font(.title3)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Choose which Square store to link to \(locationName)")
                }

                Section {
                    Button {
                        handleConnectLocation()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isLoading ? "Connecting..." : "Connect")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isLoading || selectedPosLocationId == nil)
                }
            }

            errorSection
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private var errorSection: some View {
        if let error {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    /// Check for existing account first, then OAuth if needed
    private func handleSquareSignIn() {
        isLoading = true
        error = nil
        Task {
            // Check if this device already has a POS account (skip OAuth)
            do {
                let result = try await apiService.checkExistingPOSAccount(
                    deviceId: signingDevice.0,
                    password: signingDevice.1
                )
                if result.hasAccount, let accountId = result.posAccountId {
                    posAccountId = accountId
                    withAnimation { step = .locations }
                    await loadPosLocations(accountId: accountId)
                    return
                }
            } catch {
                // If check fails, proceed to OAuth
            }

            // No existing account — start OAuth
            do {
                let oauthURLString = try await apiService.startPOSOAuth(
                    provider: "square",
                    locationId: locationId,
                    credentials: credentials,
                    signingDevice: signingDevice
                )

                guard let oauthURL = URL(string: oauthURLString) else {
                    self.error = "Invalid OAuth URL received from server"
                    isLoading = false
                    return
                }

                startWebAuth(url: oauthURL)
            } catch let apiError as APIError {
                self.error = describeError(apiError)
                isLoading = false
            } catch {
                self.error = "Failed to start OAuth: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    @MainActor
    private func startWebAuth(url: URL) {
        let coordinator = WebAuthCoordinator()
        self.webAuthCoordinator = coordinator

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "crowdcount"
        ) { callbackURL, authError in
            Task { @MainActor in
                self.webAuthCoordinator = nil

                if let authError {
                    if (authError as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.error = authError.localizedDescription
                    }
                    self.isLoading = false
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    self.error = "Failed to get account from OAuth callback"
                    self.isLoading = false
                    return
                }

                // Check for server-side error
                if let posError = components.queryItems?.first(where: { $0.name == "pos_error" })?.value {
                    self.error = "Square OAuth failed: \(posError)"
                    self.isLoading = false
                    return
                }

                guard let accountId = components.queryItems?.first(where: { $0.name == "pos_account_id" })?.value else {
                    self.error = "Failed to get account from OAuth callback"
                    self.isLoading = false
                    return
                }

                self.posAccountId = accountId
                withAnimation { self.step = .locations }
                await self.loadPosLocations(accountId: accountId)
            }
        }

        session.presentationContextProvider = coordinator
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func loadPosLocations(accountId: String) async {
        isLoading = true
        error = nil
        do {
            let locations = try await apiService.listPOSLocations(
                posAccountId: accountId,
                signingDevice: signingDevice
            )
            posLocations = locations
            if locations.count == 1 {
                selectedPosLocationId = locations[0].id
            }
        } catch let apiError as APIError {
            self.error = describeError(apiError)
        } catch {
            self.error = "Failed to load POS locations: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func handleConnectLocation() {
        guard let selectedId = selectedPosLocationId,
              let selectedLoc = posLocations.first(where: { $0.id == selectedId }) else { return }

        isLoading = true
        error = nil
        Task {
            do {
                _ = try await apiService.connectPOS(
                    locationId: locationId,
                    posAccountId: posAccountId,
                    posLocationId: selectedId,
                    posLocationName: selectedLoc.name,
                    credentials: credentials,
                    signingDevice: signingDevice
                )
                await POSStatusManager.shared.refreshStatus(
                    for: locationId,
                    credentials: credentials,
                    signingDevice: signingDevice
                )
                onConnected()
                dismiss()
            } catch let apiError as APIError {
                self.error = describeError(apiError)
                isLoading = false
            } catch {
                self.error = "Failed to connect: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - Error Descriptions

    private func describeError(_ error: APIError) -> String {
        switch error {
        case .httpError(let code):
            switch code {
            case 400: return "Invalid request. Please check your input and try again."
            case 401: return "Authentication failed. Please check your credentials."
            case 403: return "Access denied."
            case 404: return "POS endpoint not found. Please update the app."
            case 500: return "Server error. Please try again later."
            default: return "Request failed (HTTP \(code))."
            }
        case .invalidURL: return "Invalid URL configuration."
        case .invalidResponse: return "Invalid server response."
        case .decodingError: return "Unexpected response format."
        case .notFound: return "Resource not found."
        }
    }
}

// MARK: - ASWebAuthenticationSession Presentation Context

private class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
