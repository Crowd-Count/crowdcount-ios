import SwiftUI
import CoreLocation
import MapKit

// MARK: - Ad Detail View (Default Page)

struct AdDetailView: View {
    let ad: ServerAd
    let accentColor: Color
    let adImage: UIImage?
    var coordinate: CLLocationCoordinate2D? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appSettings: AppSettings

    // Generate a unique reference number based on ad ID
    private var referenceNumber: String {
        // Use a per-ad key so each ad gets a stable reference value
        let defaultsKey = "adReferenceNumber_\(ad.id)"

        // If we already saved a reference number for this ad, return it
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
            return saved
        }

        // Otherwise, generate a new one from the ad id (12 digits, grouped 3-3-3-3)
        let rawHash = ad.id.hashValue
        let positive = UInt64(bitPattern: Int64(rawHash))
        let number = positive % 1_000_000_000_000
        let formatted = String(format: "%012llu", number)
        let chars = Array(formatted)
        let g1 = String(chars[0..<3])
        let g2 = String(chars[3..<6])
        let g3 = String(chars[6..<9])
        let g4 = String(chars[9..<12])
        let newValue = "\(g1)-\(g2)-\(g3)-\(g4)"

        // Persist for future launches
        UserDefaults.standard.set(newValue, forKey: defaultsKey)
        return newValue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Logos: CrowdCount | Ad
                HStack(spacing: 20) {
                    // CrowdCount Logo
                    VStack(spacing: 6) {
                        Image("LogoRounded")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    }

                    // Divider line
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 3, height: 80)
                        .cornerRadius(18)

                    // Ad Logo (using ad image as square)
                    VStack(spacing: 6) {
                        if let image = adImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(accentColor.opacity(0.15))
                                .frame(width: 150, height: 150)
                                .overlay {
                                    Image(systemName: ad.demoIcon ?? "building.2")
                                        .font(.system(size: 50))
                                        .foregroundColor(accentColor)
                                }
                        }
                    }
                }
                .padding(.top, 20)

                Text("Sponsored Content")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Ad Content
                VStack(spacing: 20) {
                    // Title
                    Text(ad.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Description
                    Text(ad.description)
                        .font(.title)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }

                // Open in Maps Button
                if coordinate != nil {
                    Spacer()
                    Button(action: openInMaps) {
                        HStack {
                            Image(systemName: "arrow.trianglehead.turn.up.right.diamond.fill")
                            Text("Get Directions")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(accentColor.opacity(0.15))
                        .foregroundColor(accentColor)
                        .bold()
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Spacer()
                
                Divider()
                    .padding(10)

                // Reference Number
                VStack(spacing: 8) {
                    Text("Reference Number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(referenceNumber)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)  
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
    }

    private func openInMaps() {
        guard let coordinate = coordinate else { return }

        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = ad.title

        // Open location in Maps - user can then choose to get directions and select transit mode
        mapItem.openInMaps()
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    AdDetailView(
        ad: ServerAd(
            id: "preview-123",
            title: "Joe's Coffee",
            description: "50% off your first order! Best espresso in town.",
            imagePath: nil,
            deviceId: "A1234",
            durationHours: 24,
            totalPrice: 120.0,
            ctaText: "Get Offer",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: "2024-01-01T00:00:00Z",
            expirationDate: "2024-01-02T00:00:00Z"
        ),
        accentColor: .orange,
        adImage: nil,
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    )
    .environmentObject(AppSettings())
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    AdDetailView(
        ad: ServerAd(
            id: "preview-123",
            title: "Joe's Coffee",
            description: "50% off your first order! Best espresso in town.",
            imagePath: nil,
            deviceId: "A1234",
            durationHours: 24,
            totalPrice: 120.0,
            ctaText: "Get Offer",
            ctaLinkType: "default",
            ctaURL: nil,
            status: "approved",
            createdAt: "2024-01-01T00:00:00Z",
            expirationDate: "2024-01-02T00:00:00Z"
        ),
        accentColor: .orange,
        adImage: nil,
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    )
    .environmentObject(AppSettings())
    .preferredColorScheme(.dark)
}
