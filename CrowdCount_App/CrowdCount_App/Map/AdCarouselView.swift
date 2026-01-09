import SwiftUI
import SafariServices
import CoreLocation

// MARK: - Server Ad Model

struct ServerAd: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let imagePath: String?
    let deviceId: String
    var primaryDevice: String? = nil  // The primary device for grouped locations (used for map matching)
    let durationHours: Int
    let totalPrice: Double?  // Optional - not returned in public API for security
    let ctaText: String?
    let ctaLinkType: String?
    let ctaURL: String?
    let status: String
    let createdAt: String
    let expirationDate: String

    // Demo-only properties (not from API)
    var demoIcon: String? = nil
    var demoColor: String? = nil
    var demoCoordinate: CLLocationCoordinate2D? = nil

    /// The device ID to use for map location matching (uses primaryDevice if available, falls back to deviceId)
    var locationDeviceId: String {
        primaryDevice ?? deviceId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case imagePath = "image_path"
        case deviceId = "device_id"
        case primaryDevice = "primary_device"
        case durationHours = "duration_hours"
        case totalPrice = "total_price"
        case ctaText = "cta_text"
        case ctaLinkType = "cta_link_type"
        case ctaURL = "cta_url"
        case status
        case createdAt = "created_at"
        case expirationDate = "expiration_date"
    }

    var expirationDateParsed: Date {
        // Try ISO8601 with timezone and fractional seconds (e.g., 2025-12-20T15:30:00.123456Z)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expirationDate) {
            return date
        }

        // Try without fractional seconds (e.g., 2025-12-20T15:30:00Z)
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: expirationDate) {
            return date
        }

        // Try parsing without timezone (server sends UTC without Z suffix)
        // e.g., 2025-12-20T15:30:00.123456 or 2025-12-20T15:30:00
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // Try with fractional seconds
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = dateFormatter.date(from: expirationDate) {
            return date
        }

        // Try with fewer fractional digits
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = dateFormatter.date(from: expirationDate) {
            return date
        }

        // Try without fractional seconds
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = dateFormatter.date(from: expirationDate) {
            return date
        }

        return Date()
    }

    var imageURL: URL? {
        guard let imagePath = imagePath else { return nil }
        let filename = imagePath.components(separatedBy: "/").last ?? imagePath
        return URL(string: "\(AppSettings.apiBaseURL)/ad-images/\(filename)")
    }

    var displayCtaText: String {
        ctaText?.isEmpty == false ? ctaText! : "View Details"
    }

    var usesCustomLink: Bool {
        ctaLinkType == "custom" && ctaURL != nil && !ctaURL!.isEmpty
    }

    var actionURL: URL? {
        if usesCustomLink, let urlString = ctaURL {
            return URL(string: urlString)
        }
        // Default page URL (to be created later)
        return URL(string: "https://crowdcount.tech/ad/\(id)")
    }

    // Sample ads for previews (Boulder, CO - device IDs match Location.sampleLocations)
    static let sampleAds: [ServerAd] = [
        ServerAd(
            id: "sample-1",
            title: "CrowdCount HQ",
            description: "Visit our headquarters! Free demo and swag.",
            imagePath: nil,
            deviceId: "T0001",
            durationHours: 24,
            totalPrice: 120.0,
            ctaText: "Visit Us",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 3600 + 34 * 60)),
            demoIcon: "flag.2.crossed.fill",
            demoColor: "red",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.0192959, longitude: -105.28284905)
        ),
        ServerAd(
            id: "sample-2",
            title: "McCrowd's Pub",
            description: "$2 draft pints for the next hour!",
            imagePath: nil,
            deviceId: "Demo",
            durationHours: 1,
            totalPrice: 5.0,
            ctaText: "View Details",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1 * 3600)),
            demoIcon: "mug.fill",
            demoColor: "orange",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.00846, longitude: -105.27546)
        ),
        ServerAd(
            id: "sample-3",
            title: "City Park",
            description: "Nature walks every weekend. Join the community!",
            imagePath: nil,
            deviceId: "T0002",
            durationHours: 48,
            totalPrice: 240.0,
            ctaText: "Join Now",
            ctaLinkType: "custom",
            ctaURL: "https://crowdcount.tech",
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 3600 + 12 * 60)),
            demoIcon: "tree.fill",
            demoColor: "green",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.01783, longitude: -105.2684)
        ),
        ServerAd(
            id: "sample-4",
            title: "The Pond",
            description: "Fresh seafood daily. Best fish tacos in Boulder!",
            imagePath: nil,
            deviceId: "T0000",
            durationHours: 12,
            totalPrice: 60.0,
            ctaText: "Order Now",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expirationDate: ISO8601DateFormatter().string(from: Date().addingTimeInterval(45 * 60)),
            demoIcon: "fish.fill",
            demoColor: "blue",
            demoCoordinate: CLLocationCoordinate2D(latitude: 40.00087, longitude: -105.25944)
        )
    ]
}

// MARK: - Safari View (In-App Browser)

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemBlue
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Ad Service

@MainActor
class AdService: ObservableObject {
    @Published var activeAds: [ServerAd] = []
    @Published var isLoading = false

    func fetchActiveAds() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(AppSettings.apiBaseURL)/get-active-ads"
        print("[AdService] Fetching ads from: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("[AdService] Invalid URL for ads")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                print("[AdService] Response status: \(httpResponse.statusCode)")
            }

            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("[AdService] Non-200 response for ads")
                return
            }

            // Debug: print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("[AdService] Raw response: \(rawResponse.prefix(500))")
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(AdListResponse.self, from: data)
            self.activeAds = result.ads
            print("[AdService] Fetched \(result.ads.count) ads successfully")
        } catch {
            print("[AdService] Error fetching active ads: \(error)")
            self.activeAds = []
        }
    }
}

struct AdListResponse: Codable {
    let ads: [ServerAd]
    let count: Int
}

// MARK: - Legacy Ad Model (for previews)

struct Ad: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let imageName: String // Asset image name
    let ctaText: String
    let expirationDate: Date

    // Computed accent color derived from the image
    var accentColor: Color {
        guard let uiImage = UIImage(named: imageName) else {
            return .blue // Default fallback
        }
        return Color(uiColor: uiImage.dominantColor ?? .systemBlue)
    }
}

// MARK: - UIImage Extension for Dominant Color

extension UIImage {
    var dominantColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }

        let width = 50 // Sample at lower resolution for performance
        let height = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = CGFloat(rawData[index]) / 255.0
                let g = CGFloat(rawData[index + 1]) / 255.0
                let b = CGFloat(rawData[index + 2]) / 255.0
                let a = CGFloat(rawData[index + 3]) / 255.0

                // Skip transparent pixels and very dark/light pixels
                if a > 0.5 {
                    let brightness = (r + g + b) / 3.0
                    if brightness > 0.1 && brightness < 0.9 {
                        // Weight by saturation to prefer more colorful pixels
                        let maxC = max(r, g, b)
                        let minC = min(r, g, b)
                        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                        let weight = 1 + saturation * 2

                        totalR += r * weight
                        totalG += g * weight
                        totalB += b * weight
                        count += weight
                    }
                }
            }
        }

        guard count > 0 else { return .systemBlue }

        // Boost saturation of the result for a more vibrant accent color
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        let avgColor = UIColor(
            red: totalR / count,
            green: totalG / count,
            blue: totalB / count,
            alpha: 1.0
        )

        avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Increase saturation and adjust brightness for better accent color
        return UIColor(
            hue: hue,
            saturation: min(saturation * 1.5, 1.0),
            brightness: min(max(brightness, 0.5), 0.8),
            alpha: 1.0
        )
    }
}

// MARK: - Sample Ads (Placeholder Data)

extension Ad {
    static let sampleAds: [Ad] = [
        Ad(
            title: "Joe's Coffee",
            description: "50% off your first order! Best espresso in town.",
            imageName: "ad_coffee", // Add this image to Assets
            ctaText: "Get Offer",
            expirationDate: Date().addingTimeInterval(2 * 60 * 60 + 34 * 60 + 15)
        ),
        Ad(
            title: "City Gym",
            description: "Free trial week - No commitment required.",
            imageName: "ad_gym", // Add this image to Assets
            ctaText: "Start Free",
            expirationDate: Date().addingTimeInterval(5 * 60 * 60 + 12 * 60 + 45)
        ),
        Ad(
            title: "BookNook Library",
            description: "New releases every week. Join our reading club!",
            imageName: "ad_books", // Add this image to Assets
            ctaText: "Learn More",
            expirationDate: Date().addingTimeInterval(45 * 60 + 30)
        ),
        Ad(
            title: "Fresh Bites",
            description: "Healthy meals delivered to your door.",
            imageName: "ad_food", // Add this image to Assets
            ctaText: "Order Now",
            expirationDate: Date().addingTimeInterval(12 * 60 * 60 + 5 * 60)
        )
    ]
}

// MARK: - AdCardView

struct AdCardView: View {
    let ad: Ad
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeRemaining: TimeInterval = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var countdownText: String {
        if timeRemaining <= 0 {
            return "Expired"
        }
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Ad Image
            if let uiImage = UIImage(named: ad.imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Fallback placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(ad.accentColor.opacity(0.15))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(ad.accentColor)
                    }
            }

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(ad.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(ad.description)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .top) // Reserve space for 2 lines

                // CTA Button and Countdown
                HStack(spacing: 8) {
                    Button(action: {
                        // Placeholder action
                    }) {
                        Text(ad.ctaText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(ad.accentColor)
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
                    .foregroundColor(timeRemaining < 3600 ? .red : .secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            timeRemaining = ad.expirationDate.timeIntervalSinceNow
        }
        .onReceive(timer) { _ in
            timeRemaining = ad.expirationDate.timeIntervalSinceNow
        }
        .padding(12)
        .frame(width: 300, height: 125)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
            } else {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - ServerAdCardView (for server-loaded ads)

struct ServerAdCardView: View {
    let ad: ServerAd
    var locations: [Location] = []
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeRemaining: TimeInterval = 0
    @State private var loadedImage: UIImage?
    @State private var accentColor: Color = .blue
    @State private var showingSafari = false
    @State private var showingAdDetail = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Convert demo color string to SwiftUI Color
    private var demoAccentColor: Color {
        guard let colorName = ad.demoColor else { return .blue }
        switch colorName {
        case "brown": return .brown
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }

    /// Get the coordinate for this ad's associated location
    private var adCoordinate: CLLocationCoordinate2D? {
        // Use demo coordinate if available
        if let demoCoord = ad.demoCoordinate {
            return demoCoord
        }
        // Use locationDeviceId which prefers primaryDevice for grouped locations
        guard let location = locations.first(where: { $0.userId == ad.locationDeviceId }) else {
            return nil
        }
        return location.coordinate
    }

    private var countdownText: String {
        if timeRemaining <= 0 {
            return "Expired"
        }
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Ad Image
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let demoIcon = ad.demoIcon {
                // Demo ad with icon
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: demoIcon)
                            .font(.system(size: 32))
                            .foregroundColor(accentColor)
                    }
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            }

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(ad.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(ad.description)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .top)

                // CTA Button and Countdown
                HStack(spacing: 8) {
                    Button(action: {
                        // Track the click (fire and forget)
                        trackAdClick(adId: ad.id)

                        if ad.usesCustomLink, ad.actionURL != nil {
                            showingSafari = true
                        } else {
                            showingAdDetail = true
                        }
                    }) {
                        Text(ad.displayCtaText)
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
                    .foregroundColor(timeRemaining < 3600 ? .red : .secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            timeRemaining = ad.expirationDateParsed.timeIntervalSinceNow
            // Use demo color if available, otherwise load image
            if ad.demoColor != nil {
                accentColor = demoAccentColor
            } else {
                loadImage()
            }
        }
        .onReceive(timer) { _ in
            timeRemaining = ad.expirationDateParsed.timeIntervalSinceNow
        }
        .padding(10)
        .frame(width: 310, height: 125)
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
        .sheet(isPresented: $showingSafari) {
            if let url = ad.actionURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingAdDetail) {
            AdDetailView(ad: ad, accentColor: accentColor, adImage: loadedImage, coordinate: adCoordinate)
        }
    }

    private func loadImage() {
        guard let url = ad.imageURL else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.loadedImage = image
                        if let dominantColor = image.dominantColor {
                            self.accentColor = Color(uiColor: dominantColor)
                        }
                    }
                }
            } catch {
                print("Error loading ad image: \(error)")
            }
        }
    }

    private func trackAdClick(adId: String) {
        // Fire and forget - don't block UI
        Task {
            guard let url = URL(string: "\(AppSettings.apiBaseURL)/track-ad-click") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["adId": adId]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                // Silently fail - tracking shouldn't affect user experience
                print("Error tracking ad click: \(error)")
            }
        }
    }
}

// MARK: - AdCarouselView

struct AdCarouselView: View {
    @Binding var isVisible: Bool
    @ObservedObject var adService: AdService
    var userLocation: CLLocationCoordinate2D?
    var locations: [Location]
    var previewAds: [ServerAd]? = nil  // Optional preview ads for SwiftUI previews
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentAdId: String?

    private var displayAds: [ServerAd] {
        let ads = previewAds ?? adService.activeAds
        return sortedByDistance(ads)
    }

    /// Sorts ads by distance from user location (closest first)
    private func sortedByDistance(_ ads: [ServerAd]) -> [ServerAd] {
        guard let userLocation = userLocation else {
            return ads // No user location, return unsorted
        }

        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)

        return ads.sorted { ad1, ad2 in
            let distance1 = distanceToAd(ad1, from: userCLLocation)
            let distance2 = distanceToAd(ad2, from: userCLLocation)
            return distance1 < distance2
        }
    }

    /// Returns distance from user to the ad's associated location, or .infinity if not found
    private func distanceToAd(_ ad: ServerAd, from userCLLocation: CLLocation) -> CLLocationDistance {
        // Use locationDeviceId which prefers primaryDevice for grouped locations
        guard let location = locations.first(where: { $0.userId == ad.locationDeviceId }) else {
            return .infinity // No matching location, sort to end
        }

        let adCLLocation = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return userCLLocation.distance(from: adCLLocation)
    }

    // Check if device has curved screen corners (home indicator present)
    private var hasCurvedScreen: Bool {
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window.safeAreaInsets.bottom > 0
        }
        return false
        #else
        return false
        #endif
    }

    // Bottom corners match device curve (with padding offset), top corners are standard
    // iPhone display corner radius is approximately 55pt on modern devices
    private var bottomRadius: CGFloat {
        hasCurvedScreen ? 55 : 20
    }

    private var topRadius: CGFloat {
        20
    }

    var body: some View {
        VStack(spacing: 0) {
            if !displayAds.isEmpty {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Promotions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Horizontal scroll of ad cards
                    GeometryReader { geo in
                        let cardWidth: CGFloat = 310
                        let spacing: CGFloat = 12
                        let sideInset = max(16, (geo.size.width - cardWidth) / 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: spacing) {
                                ForEach(displayAds) { ad in
                                    ServerAdCardView(ad: ad, locations: locations)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .contentMargins(.horizontal, sideInset)
                        .scrollClipDisabled()
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $currentAdId)
                    }
                    .frame(height: 125)

                    // Page indicator dots (only show if more than 1 ad)
                    if displayAds.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(displayAds) { ad in
                                Circle()
                                    .fill(currentAdId == ad.id || (currentAdId == nil && ad.id == displayAds.first?.id) ? Color.primary : Color.secondary.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .offset(y: 12)
                        .padding(.bottom, 24)
                    } else {
                        Spacer().frame(height: 16)
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius))
                .background {
                    if #available(iOS 26.0, *) {
                        UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.clear)
                            .glassEffect(.clear, in: UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius))
                    } else {
                        UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius)
                            .fill(.ultraThinMaterial)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: 0)
        .task {
            // Fetch ads when view appears
            print("[AdCarouselView] View task started")
            if previewAds == nil {
                await adService.fetchActiveAds()
            }
        }
    }
}

// MARK: - Previews

#Preview("Ad Carousel - Light") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            Spacer()
            AdCarouselView(isVisible: .constant(true), adService: AdService(), userLocation: nil, locations: [], previewAds: ServerAd.sampleAds)
                .padding(.horizontal, 8)
                .padding(.bottom, -26)
        }
    }
    .preferredColorScheme(.light)
}

#Preview("Ad Carousel - Dark") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            Spacer()
            AdCarouselView(isVisible: .constant(true), adService: AdService(), userLocation: nil, locations: [], previewAds: ServerAd.sampleAds)
                .padding(.horizontal, 8)
                .padding(.bottom, -26)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Single Ad Card") {
    VStack {
        ServerAdCardView(ad: ServerAd.sampleAds[0])
        ServerAdCardView(ad: ServerAd.sampleAds[1])
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("On Map Background") {
    ZStack {
        // Simulated map background
        LinearGradient(
            colors: [.green.opacity(0.3), .blue.opacity(0.2), .green.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            AdCarouselView(isVisible: .constant(true), adService: AdService(), userLocation: nil, locations: [], previewAds: ServerAd.sampleAds)
                .padding(.horizontal, 8)
                .padding(.bottom, -26)
        }
    }
    .preferredColorScheme(.dark)
}
