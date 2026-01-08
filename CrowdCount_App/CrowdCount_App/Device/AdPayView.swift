import SwiftUI
import PhotosUI
import PassKit
import Stripe
import UserNotifications
import CoreLocation

// MARK: - UserCreatedAd Model

struct UserCreatedAd: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let imageData: Data?
    let deviceId: String
    let durationHours: Int
    let totalPrice: Double
    let createdAt: Date
    let expirationDate: Date
    let ctaText: String
    let ctaLinkType: CTALinkType
    let ctaURL: String?

    var isActive: Bool {
        return Date() < expirationDate
    }
}

enum CTALinkType: String, Codable, CaseIterable {
    case defaultPage = "default"
    case customLink = "custom"

    var displayName: String {
        switch self {
        case .defaultPage:
            return "Default Page"
        case .customLink:
            return "Custom Link"
        }
    }
}

// MARK: - Image Processing

extension UIImage {
    /// Crops the image to a square (center crop) and resizes to target size
    func cropToSquareAndResize(targetSize: CGFloat = 720) -> UIImage? {
        let originalSize = self.size
        let shortestSide = min(originalSize.width, originalSize.height)

        // Calculate crop rect (center crop)
        let cropRect = CGRect(
            x: (originalSize.width - shortestSide) / 2,
            y: (originalSize.height - shortestSide) / 2,
            width: shortestSide,
            height: shortestSide
        )

        // Crop to square
        guard let cgImage = self.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: self.scale, orientation: self.imageOrientation)

        // Resize to target size
        let targetRect = CGRect(x: 0, y: 0, width: targetSize, height: targetSize)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: targetSize, height: targetSize), false, 1.0)
        croppedImage.draw(in: targetRect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage
    }

    /// Processes image for ad submission: crops to square, resizes to 720p, compresses as JPEG
    func processForAdSubmission() -> Data? {
        guard let processedImage = self.cropToSquareAndResize(targetSize: 720) else {
            return nil
        }
        // Compress with 0.8 quality for good balance of size and quality
        return processedImage.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Ad Storage Manager

class AdStorageManager {
    static let shared = AdStorageManager()
    private let adsKey = "userCreatedAds"

    func saveAd(_ ad: UserCreatedAd) {
        var ads = loadAds()
        ads.append(ad)
        if let encoded = try? JSONEncoder().encode(ads) {
            UserDefaults.standard.set(encoded, forKey: adsKey)
        }
    }

    func loadAds() -> [UserCreatedAd] {
        guard let savedAds = UserDefaults.standard.data(forKey: adsKey),
              let decodedAds = try? JSONDecoder().decode([UserCreatedAd].self, from: savedAds) else {
            return []
        }
        return decodedAds
    }

    func loadActiveAds() -> [UserCreatedAd] {
        return loadAds().filter { $0.isActive }
    }

    func removeExpiredAds() {
        let activeAds = loadActiveAds()
        if let encoded = try? JSONEncoder().encode(activeAds) {
            UserDefaults.standard.set(encoded, forKey: adsKey)
        }
    }
}

// MARK: - Ad Creation View Model

@MainActor
class AdCreationViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var selectedImage: UIImage?
    @Published var selectedDeviceId: String = ""
    @Published var hoursSelected: Int = 1
    @Published var ctaText: String = ""
    @Published var ctaLinkType: CTALinkType = .defaultPage
    @Published var ctaURL: String = ""
    @Published var isProcessingPayment: Bool = false
    @Published var showPaymentSuccess: Bool = false
    @Published var showPaymentError: Bool = false
    @Published var errorMessage: String = ""
    @Published var pricePerHour: Double = 5.0  // Default, fetched from server
    @Published var isPricingLoaded: Bool = false

    private let apiService = APIService.shared

    var totalPrice: Double {
        return Double(hoursSelected) * pricePerHour
    }

    /// Fetch pricing from server
    func loadPricing() async {
        do {
            let price = try await apiService.fetchPromotionPricing()
            await MainActor.run {
                self.pricePerHour = price
                self.isPricingLoaded = true
            }
        } catch {
            // Use default price on error
            await MainActor.run {
                self.isPricingLoaded = true
            }
            print("Failed to fetch promotion pricing: \(error)")
        }
    }

    var formIsValid: Bool {
        let baseValid = !title.trimmingCharacters(in: .whitespaces).isEmpty &&
               !description.trimmingCharacters(in: .whitespaces).isEmpty &&
               selectedImage != nil &&
               !selectedDeviceId.isEmpty

        // If custom link is selected, URL must be valid
        if ctaLinkType == .customLink {
            return baseValid && isValidURL(ctaURL)
        }

        return baseValid
    }

    var displayCtaText: String {
        ctaText.trimmingCharacters(in: .whitespaces).isEmpty ? "View Details" : ctaText
    }

    private func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Add https:// if no scheme provided
        let urlString = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains(".") else {
            return false
        }

        return true
    }

    var normalizedURL: String? {
        guard ctaLinkType == .customLink else { return nil }
        let trimmed = ctaURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
    }

    func resetForm() {
        title = ""
        description = ""
        selectedImage = nil
        selectedDeviceId = ""
        hoursSelected = 1
        ctaText = ""
        ctaLinkType = .defaultPage
        ctaURL = ""
    }

    func createAd() -> UserCreatedAd {
        // Process image: crop to square, resize to 720x720, compress
        let imageData = selectedImage?.processForAdSubmission()
        let now = Date()
        let expiration = now.addingTimeInterval(Double(hoursSelected) * 3600)

        return UserCreatedAd(
            id: UUID(),
            title: title,
            description: description,
            imageData: imageData,
            deviceId: selectedDeviceId,
            durationHours: hoursSelected,
            totalPrice: totalPrice,
            createdAt: now,
            expirationDate: expiration,
            ctaText: displayCtaText,
            ctaLinkType: ctaLinkType,
            ctaURL: normalizedURL
        )
    }
}

// MARK: - Stripe Configuration

class StripeConfig {
    static let shared = StripeConfig()

    let publishableKey = "pk_live_51Pda1QRqtv4SxEbyHgEGpfPmroHP1mAXuSeim8UeYeAIwtEvEGRyjroKxxXDui8FaIGnASVl4WzeCUjtFsrlDgGr00HL8kE91X"

    let backendURL = "https://api.crowdcount.tech"

    func configure() {
        StripeAPI.defaultPublishableKey = publishableKey
    }
}

// MARK: - Payment Handler

class PaymentHandler: NSObject, PKPaymentAuthorizationControllerDelegate {
    var completion: ((Bool, String?) -> Void)?  // Returns (success, paymentIntentId)
    private var clientSecret: String?
    private var paymentIntentId: String?
    private var currentHours: Int = 1

    func startPayment(amount: Double, hours: Int, completion: @escaping (Bool, String?) -> Void) {
        self.completion = completion
        self.currentHours = hours

        // First, create a PaymentIntent on your backend
        createPaymentIntent(amount: amount) { [weak self] secret in
            guard let self = self, let secret = secret else {
                completion(false, nil)
                return
            }

            self.clientSecret = secret
            // Extract PaymentIntent ID from clientSecret (format: pi_XXXX_secret_YYYY)
            self.paymentIntentId = secret.components(separatedBy: "_secret_").first
            self.presentApplePay(amount: amount, hours: hours)
        }
    }

    private func createPaymentIntent(amount: Double, completion: @escaping (String?) -> Void) {
        // Convert to cents for Stripe
        let amountInCents = Int(amount * 100)

        guard let url = URL(string: "\(StripeConfig.shared.backendURL)/create-payment-intent") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["amount": amountInCents]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Payment Intent Error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("Payment Intent Response Status: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("Payment Intent: No data received")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Payment Intent Response: \(responseString)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clientSecret = json["clientSecret"] as? String else {
                print("Payment Intent: Failed to parse clientSecret from response")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(clientSecret) }
        }.resume()
    }

    private func presentApplePay(amount: Double, hours: Int) {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = "merchant.tech.crowdcount.app"
        paymentRequest.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        paymentRequest.merchantCapabilities = .threeDSecure
        paymentRequest.countryCode = "US"
        paymentRequest.currencyCode = "USD"

        let hourLabel = hours == 1 ? "1 Hour" : "\(hours) Hours"
        let adPurchase = PKPaymentSummaryItem(
            label: "Promotion Placement (\(hourLabel))",
            amount: NSDecimalNumber(value: amount)
        )
        let total = PKPaymentSummaryItem(
            label: "CrowdCount",
            amount: NSDecimalNumber(value: amount)
        )
        paymentRequest.paymentSummaryItems = [adPurchase, total]

        let controller = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        controller.delegate = self
        controller.present(completion: { [weak self] presented in
            if !presented {
                self?.completion?(false, nil)
            }
        })
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard let clientSecret = clientSecret else {
            print("Payment failed: No client secret")
            handler(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            completion?(false, nil)
            return
        }

        // Create payment method from Apple Pay token
        STPAPIClient.shared.createPaymentMethod(with: payment) { [weak self] paymentMethod, error in
            guard let self = self else { return }

            if let error = error {
                print("Payment failed: \(error.localizedDescription)")
                handler(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                self.completion?(false, nil)
                return
            }

            guard let paymentMethod = paymentMethod else {
                print("Payment failed: No payment method created")
                handler(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                self.completion?(false, nil)
                return
            }

            // Confirm payment with ONLY the payment method ID (no paymentMethodParams)
            let paymentIntentParams = STPPaymentIntentParams(clientSecret: clientSecret)
            paymentIntentParams.paymentMethodId = paymentMethod.stripeId

            STPPaymentHandler.shared().confirmPaymentIntent(params: paymentIntentParams, authenticationContext: self) { status, _, error in
                switch status {
                case .succeeded:
                    print("Payment succeeded!")
                    handler(PKPaymentAuthorizationResult(status: .success, errors: nil))
                    self.completion?(true, self.paymentIntentId)
                case .failed:
                    print("Payment failed: \(error?.localizedDescription ?? "Unknown")")
                    handler(PKPaymentAuthorizationResult(status: .failure, errors: error.map { [$0] }))
                    self.completion?(false, nil)
                case .canceled:
                    print("Payment canceled")
                    handler(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    self.completion?(false, nil)
                @unknown default:
                    handler(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                    self.completion?(false, nil)
                }
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}

// MARK: - STPAuthenticationContext

extension PaymentHandler: STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return UIViewController()
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - AdPayView

struct AdPayView: View {
    @Binding var users: [User]
    var deviceLocationNames: [String: String] = [:]  // Maps device ID to location name
    var devicePrimaryDevices: [String: String] = [:]  // Maps device ID to its primary device
    @StateObject private var viewModel = AdCreationViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var paymentHandler = PaymentHandler()
    @State private var showDefaultPagePreview = false
    @State private var showPreviewSafari = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// Users filtered to only include devices that are on the map
    private var usersOnMap: [User] {
        users.filter { $0.userId != "Demo" && deviceLocationNames.keys.contains($0.userId) }
    }

    /// The location name for the currently selected device
    private var selectedLocationName: String {
        guard !viewModel.selectedDeviceId.isEmpty else { return "" }
        return deviceLocationNames[viewModel.selectedDeviceId] ?? viewModel.selectedDeviceId
    }

    /// The primary device for the currently selected device (for grouped locations)
    private var selectedPrimaryDevice: String {
        guard !viewModel.selectedDeviceId.isEmpty else { return "" }
        return devicePrimaryDevices[viewModel.selectedDeviceId] ?? viewModel.selectedDeviceId
    }

    var canMakePayments: Bool {
        return PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: [.visa, .masterCard, .amex, .discover]
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Form Fields
                titleField
                descriptionField
                buttonTextField
                buttonLinkSection
                imagePickerSection
                deviceSelector
                hoursSelector
                priceDisplay

                // Ad Preview
                adPreviewSection

                // Apple Pay Button
                paymentSection

                Spacer(minLength: 40)
            }
            .padding(.top, 20)
        }
        .alert("Payment Successful!", isPresented: $viewModel.showPaymentSuccess) {
            Button("Got it") {
                viewModel.resetForm()
                selectedPhotoItem = nil
                dismiss()
            }
        } message: {
            Text("All good! Our team will review your promotion and it should appear on the map within the next few minutes.")
        }
        .alert("Payment Failed", isPresented: $viewModel.showPaymentError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage.isEmpty ? "There was an issue processing your payment. Please try again." : viewModel.errorMessage)
        }
        .task {
            await viewModel.loadPricing()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Create a Promotion")
                .font(.title2)
                .fontWeight(.bold)

            Text("Promote your business on the CrowdCount map")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Character Limits

    private let titleCharLimit = 20
    private let descriptionCharLimit = 55
    private let ctaCharLimit = 12

    // MARK: - Title Field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Promotion Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !selectedLocationName.isEmpty {
                    Text("From location")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 5)

            Text(selectedLocationName.isEmpty ? "Select a location first" : selectedLocationName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .foregroundColor(selectedLocationName.isEmpty ? .secondary : .primary)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(15)
        }
        .padding(.horizontal, 20)
        .onChange(of: viewModel.selectedDeviceId) { _, _ in
            // Update the title in the viewModel when device changes
            viewModel.title = selectedLocationName
        }
    }

    // MARK: - Description Field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Promotion Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.description.count)/\(descriptionCharLimit)")
                    .font(.caption2)
                    .foregroundColor(viewModel.description.count >= descriptionCharLimit ? .orange : .secondary)
            }
            .padding(.horizontal, 5)

            TextField("Describe your offer or promotion", text: $viewModel.description, axis: .vertical)
                .lineLimit(2...4)
                .padding()
                .background(Color.secondary.opacity(0.25))
                .cornerRadius(15)
                .onChange(of: viewModel.description) { _, newValue in
                    if newValue.count > descriptionCharLimit {
                        viewModel.description = String(newValue.prefix(descriptionCharLimit))
                    }
                }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Button Text Field

    private var buttonTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Button Text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.ctaText.count)/\(ctaCharLimit)")
                    .font(.caption2)
                    .foregroundColor(viewModel.ctaText.count >= ctaCharLimit ? .orange : .secondary)
            }
            .padding(.horizontal, 5)

            TextField("View Details", text: $viewModel.ctaText)
                .padding()
                .background(Color.secondary.opacity(0.25))
                .cornerRadius(15)
                .onChange(of: viewModel.ctaText) { _, newValue in
                    if newValue.count > ctaCharLimit {
                        viewModel.ctaText = String(newValue.prefix(ctaCharLimit))
                    }
                }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Button Link Section

    private var buttonLinkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Button Action")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 5)

            // Toggle Picker
            Picker("Link Type", selection: $viewModel.ctaLinkType) {
                ForEach(CTALinkType.allCases, id: \.self) { linkType in
                    Text(linkType.displayName).tag(linkType)
                }
            }
            .pickerStyle(.segmented)

            // URL Field (only shown when custom link is selected)
            if viewModel.ctaLinkType == .customLink {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("https://example.com", text: $viewModel.ctaURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.secondary.opacity(0.25))
                        .cornerRadius(15)

                    if !viewModel.ctaURL.isEmpty && !isValidURLPreview(viewModel.ctaURL) {
                        Text("Please enter a valid URL")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.leading, 5)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(AttributedString("Button will open a default CrowdCount info page that looks like ") + {
                    var s = AttributedString("this")
                    s.foregroundColor = .blue
                    return s
                }())
                .font(.caption2)
                .foregroundColor(.secondary)
                .onTapGesture {
                    showDefaultPagePreview = true
                }
                .padding(.leading, 5)
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: viewModel.ctaLinkType)
        .sheet(isPresented: $showDefaultPagePreview) {
            AdDetailView(
                ad: previewServerAd,
                accentColor: previewAccentColor,
                adImage: viewModel.selectedImage?.cropToSquareAndResize(targetSize: 720),
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // Sample coordinate for preview
            )
        }
    }

    // Accent color extracted from the cropped/processed image (same as ad card)
    private var previewAccentColor: Color {
        guard let image = viewModel.selectedImage,
              let croppedImage = image.cropToSquareAndResize(targetSize: 720),
              let dominantColor = croppedImage.dominantColor else {
            return .blue
        }
        return Color(uiColor: dominantColor)
    }

    // Preview ad for showing what the default page looks like
    private var previewServerAd: ServerAd {
        ServerAd(
            id: "preview",
            title: viewModel.title.isEmpty ? "Your Business" : viewModel.title,
            description: viewModel.description.isEmpty ? "Your promotion description will appear here" : viewModel.description,
            imagePath: nil,
            deviceId: viewModel.selectedDeviceId,
            durationHours: viewModel.hoursSelected,
            totalPrice: viewModel.totalPrice,
            ctaText: viewModel.displayCtaText,
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(viewModel.hoursSelected) * 3600))
        )
    }

    private func isValidURLPreview(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let urlString = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains(".") else {
            return false
        }

        return true
    }

    // MARK: - Image Picker Section

    private var imagePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Promotion Image")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Will be cropped to square")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 5)

            let selectedImage = viewModel.selectedImage

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                if let image = selectedImage,
                   let croppedImage = image.cropToSquareAndResize(targetSize: 720) {
                    // Show the cropped square preview
                    Image(uiImage: croppedImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                } else {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 150)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 36))
                                Text("Tap to select image")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            viewModel.selectedImage = image
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Device Selector

    private var deviceSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Location")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 5)

            Menu {
                ForEach(usersOnMap, id: \.id) { user in
                    let locationName = deviceLocationNames[user.userId] ?? user.userId
                    Button(action: {
                        viewModel.selectedDeviceId = user.userId
                    }) {
                        HStack {
                            Text(locationName)
                            if viewModel.selectedDeviceId == user.userId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedDeviceId.isEmpty ? "Select a location" : selectedLocationName)
                        .foregroundColor(viewModel.selectedDeviceId.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.25))
                .cornerRadius(15)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Hours Selector

    private var hoursSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Duration")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 5)

            HStack {
                Text("Promotion will run for:")
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("\(viewModel.hoursSelected) hour\(viewModel.hoursSelected == 1 ? "" : "s")",
                        value: $viewModel.hoursSelected,
                        in: 1...72)
            }
            .padding()
            .background(Color.secondary.opacity(0.25))
            .cornerRadius(15)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Price Display

    private var priceDisplay: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Total Price")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if viewModel.isPricingLoaded {
                    Text("$\(viewModel.pricePerHour, specifier: "%.2f") per hour")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Loading pricing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if viewModel.isPricingLoaded {
                Text("$\(viewModel.totalPrice, specifier: "%.2f")")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(15)
        .padding(.horizontal, 20)
    }

    // MARK: - Ad Preview Section

    private var adPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Promotion Preview")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 5)

            AdPreviewCard(
                title: viewModel.title,
                description: viewModel.description,
                image: viewModel.selectedImage?.cropToSquareAndResize(targetSize: 720),
                hours: viewModel.hoursSelected,
                ctaText: viewModel.displayCtaText,
                onButtonTap: {
                    if viewModel.ctaLinkType == .customLink && viewModel.normalizedURL != nil {
                        showPreviewSafari = true
                    } else {
                        showDefaultPagePreview = true
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showPreviewSafari) {
                if let urlString = viewModel.normalizedURL, let url = URL(string: urlString) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Payment Section

    private var paymentSection: some View {
        VStack(spacing: 12) {
            // Content warning and refund policy
            Text("Promotions are subject to review. Reasons for rejection include inappropriate, misleading, or offensive content. If rejected, you'll be refunded minus processing fees (3% + $0.30). Approved promotions later removed for violations are not eligible for refunds.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if canMakePayments {
                PayWithApplePayButton {
                    if viewModel.formIsValid && !viewModel.isProcessingPayment {
                        processPayment()
                    }
                }
                .frame(height: 50)
                .cornerRadius(25)
                .padding(.horizontal, 20)
                .disabled(!viewModel.formIsValid || viewModel.isProcessingPayment)
                .opacity(viewModel.formIsValid ? 1.0 : 0.5)
            } else {
                Text("Apple Pay is not available on this device")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }

            if !viewModel.formIsValid {
                Text("Please fill in all fields to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.isProcessingPayment {
                ProgressView()
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Payment Processing

    private func processPayment() {
        viewModel.isProcessingPayment = true

        paymentHandler.startPayment(amount: viewModel.totalPrice, hours: viewModel.hoursSelected) { success, paymentIntentId in
            DispatchQueue.main.async {
                viewModel.isProcessingPayment = false

                if success, let paymentIntentId = paymentIntentId {
                    // Save the ad locally
                    let ad = viewModel.createAd()
                    AdStorageManager.shared.saveAd(ad)

                    // Request notification permission to notify when ad is live
                    requestNotificationPermission {
                        // Submit ad for review to server (with payment proof)
                        submitAdForReview(ad: ad, paymentIntentId: paymentIntentId)
                    }

                    viewModel.showPaymentSuccess = true
                } else {
                    viewModel.showPaymentError = true
                }
            }
        }
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission(completion: @escaping () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            completion()
        }
    }

    // MARK: - Submit Ad for Review

    private func submitAdForReview(ad: UserCreatedAd, paymentIntentId: String) {
        // Server will verify this paymentIntentId with Stripe before accepting the ad

        guard let url = URL(string: "https://api.crowdcount.tech/submit-ad-for-review") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert image data to base64 for transmission
        let imageBase64 = ad.imageData?.base64EncodedString() ?? ""

        // Get app ID for push notification targeting
        let appId = UserDefaults.standard.string(forKey: "appId") ?? ""

        var body: [String: Any] = [
            "paymentIntentId": paymentIntentId,  // Server verifies this with Stripe
            "id": ad.id.uuidString,
            "title": ad.title,
            "description": ad.description,
            "image": imageBase64,
            "deviceId": ad.deviceId,
            "durationHours": ad.durationHours,
            "totalPrice": ad.totalPrice,
            "ctaText": ad.ctaText,
            "ctaLinkType": ad.ctaLinkType.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: ad.createdAt),
            "expirationDate": ISO8601DateFormatter().string(from: ad.expirationDate),
            "submitterAppId": appId  // For push notifications when ad is approved
        ]

        if let ctaURL = ad.ctaURL {
            body["ctaURL"] = ctaURL
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to submit ad for review: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("Ad submitted for review - Status: \(httpResponse.statusCode)")
            }
        }.resume()
    }
}

// MARK: - Apple Pay Button View

struct PayWithApplePayButton: UIViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}

    class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonTapped() {
            action()
        }
    }
}

// MARK: - Ad Preview Card

struct AdPreviewCard: View {
    let title: String
    let description: String
    let image: UIImage?
    let hours: Int
    let ctaText: String
    var onButtonTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var displayTitle: String {
        title.isEmpty ? "Your Business Name" : title
    }

    private var displayDescription: String {
        description.isEmpty ? "Your promotion description will appear here..." : description
    }

    private var accentColor: Color {
        guard let image = image else { return .blue }
        return Color(uiColor: image.dominantColor ?? .systemBlue)
    }

    private var countdownText: String {
        let totalSeconds = hours * 3600
        let displayHours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if displayHours > 0 {
            return String(format: "%d:%02d:%02d", displayHours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Ad Image
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(accentColor)
                    }
            }

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(displayDescription)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .top)

                // CTA Button and Countdown
                HStack(spacing: 8) {
                    Button(action: {
                        onButtonTap?()
                    }) {
                        Text(ctaText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(accentColor)
                            .cornerRadius(8)
                    }

                    // Countdown timer
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(countdownText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 110)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.clear)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 30))
            } else {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Previews

#Preview("Light Mode") {
    AdPayView(
        users: .constant([
            User(id: UUID(), userId: "TestDevice1", currentCount: 42),
            User(id: UUID(), userId: "TestDevice2", currentCount: 15),
            User(id: UUID(), userId: "TestDevice3", currentCount: 8)
        ]),
        deviceLocationNames: [
            "TestDevice1": "Joe's Coffee Shop",
            "TestDevice2": "Main Street Bakery",
            "TestDevice3": "Joe's Coffee Shop"  // Secondary device at same location
        ],
        devicePrimaryDevices: [
            "TestDevice1": "TestDevice1",  // Primary device
            "TestDevice2": "TestDevice2",  // Primary device
            "TestDevice3": "TestDevice1"   // Secondary device -> maps to TestDevice1
        ]
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    AdPayView(
        users: .constant([
            User(id: UUID(), userId: "TestDevice1", currentCount: 42),
            User(id: UUID(), userId: "TestDevice2", currentCount: 15),
            User(id: UUID(), userId: "TestDevice3", currentCount: 8)
        ]),
        deviceLocationNames: [
            "TestDevice1": "Joe's Coffee Shop",
            "TestDevice2": "Main Street Bakery",
            "TestDevice3": "Joe's Coffee Shop"  // Secondary device at same location
        ],
        devicePrimaryDevices: [
            "TestDevice1": "TestDevice1",  // Primary device
            "TestDevice2": "TestDevice2",  // Primary device
            "TestDevice3": "TestDevice1"   // Secondary device -> maps to TestDevice1
        ]
    )
    .preferredColorScheme(.dark)
}

