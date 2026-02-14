import SwiftUI
import CoreLocation

// MARK: - Tab Selection

enum ListTab: String, CaseIterable {
    case locations = "Locations"
    case ads = "Promotions"
}

// MARK: - LocationListView

struct LocationListView: View {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject var adService: AdService
    var userLocation: CLLocationCoordinate2D?
    var onLocationSelected: ((Location) -> Void)? = nil
    @State private var searchText = ""
    @State private var selectedTab: ListTab = .locations
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var filteredLocations: [Location] {
        let base: [Location]
        if searchText.isEmpty {
            base = viewModel.locations
        } else {
            base = viewModel.locations.filter { location in
                location.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let userLocation = userLocation {
            let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            return base.sorted { a, b in
                let distA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude).distance(from: userCLLocation)
                let distB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude).distance(from: userCLLocation)
                return distA < distB
            }
        } else {
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var filteredAds: [ServerAd] {
        let base: [ServerAd]
        if searchText.isEmpty {
            base = adService.activeAds
        } else {
            base = adService.activeAds.filter { ad in
                ad.title.localizedCaseInsensitiveContains(searchText) ||
                ad.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let userLocation = userLocation {
            let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            return base.sorted { a, b in
                let distA = distanceToAd(a, from: userCLLocation)
                let distB = distanceToAd(b, from: userCLLocation)
                return distA < distB
            }
        } else {
            return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func distanceToAd(_ ad: ServerAd, from userCLLocation: CLLocation) -> CLLocationDistance {
        if let demoCoord = ad.demoCoordinate {
            return CLLocation(latitude: demoCoord.latitude, longitude: demoCoord.longitude).distance(from: userCLLocation)
        }
        guard let location = viewModel.locations.first(where: { $0.id == ad.locationId }) else {
            return .infinity
        }
        return CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude).distance(from: userCLLocation)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(ListTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Search Bar
                SearchBar(text: $searchText, placeholder: selectedTab == .locations ? "Search locations..." : "Search promotions...")
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Content based on selected tab
                switch selectedTab {
                case .locations:
                    LocationsListContent(filteredLocations: filteredLocations, searchText: searchText, colorScheme: colorScheme, userLocation: userLocation, onLocationSelected: onLocationSelected)
                case .ads:
                    AdsListContent(filteredAds: filteredAds, searchText: searchText, locations: viewModel.locations, colorScheme: colorScheme)
                }
            }
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
            .navigationTitle(selectedTab.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(.blue)
                }
            }
        }
        .preferredColorScheme(colorScheme)
        .task {
            // Fetch ads when view appears if not already loaded
            if adService.activeAds.isEmpty {
                await adService.fetchActiveAds()
            }
        }
    }
}

// MARK: - Locations List Content

struct LocationsListContent: View {
    let filteredLocations: [Location]
    let searchText: String
    let colorScheme: ColorScheme
    var userLocation: CLLocationCoordinate2D? = nil
    var onLocationSelected: ((Location) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if filteredLocations.isEmpty {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                Text(searchText.isEmpty ? "No locations available" : "No locations found")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            List {
                ForEach(filteredLocations) { location in
                    Button {
                        onLocationSelected?(location)
                        dismiss()
                    } label: {
                        LocationRowView(location: location, userLocation: userLocation)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
        }
    }
}

// MARK: - Ads List Content

struct AdsListContent: View {
    let filteredAds: [ServerAd]
    let searchText: String
    let locations: [Location]
    let colorScheme: ColorScheme

    var body: some View {
        if filteredAds.isEmpty {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "megaphone")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                Text(searchText.isEmpty ? "No promotions available" : "No promotions found")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredAds) { ad in
                        AdListCardView(ad: ad, locations: locations)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
        }
    }
}

// MARK: - Ad List Card View (full-width version of ServerAdCardView)

struct AdListCardView: View {
    let ad: ServerAd
    var locations: [Location] = []
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appSettings: AppSettings
    @State private var timeRemaining: TimeInterval = 0
    @State private var loadedImage: UIImage?
    @State private var accentColor: Color = .blue
    @State private var showingSafari = false
    @State private var showingAdDetail = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

    private var adCoordinate: CLLocationCoordinate2D? {
        if let demoCoord = ad.demoCoordinate {
            return demoCoord
        }
        guard let location = locations.first(where: { $0.id == ad.locationId }) else {
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
        HStack(spacing: 12) {
            // Ad Image
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let demoIcon = ad.demoIcon {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: demoIcon)
                            .font(.system(size: 28))
                            .foregroundColor(accentColor)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 70, height: 70)
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
            if ad.demoColor != nil {
                accentColor = demoAccentColor
            } else {
                loadImage()
            }
        }
        .onReceive(timer) { _ in
            timeRemaining = ad.expirationDateParsed.timeIntervalSinceNow
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground))
        }
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingSafari) {
            if let url = ad.actionURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingAdDetail) {
            AdDetailView(ad: ad, accentColor: accentColor, adImage: loadedImage, coordinate: adCoordinate)
                .environmentObject(appSettings)
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
                print("Error tracking ad click: \(error)")
            }
        }
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search locations..."
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.primary)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(UIColor.tertiarySystemBackground) : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - LocationRowView

struct LocationRowView: View {
    let location: Location
    var userLocation: CLLocationCoordinate2D? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var distanceText: String? {
        guard let userLocation = userLocation else { return nil }
        let userCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let locationCL = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let meters = locationCL.distance(from: userCL)
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            if meters < 1000 {
                return "\(Int(meters)) m"
            } else {
                let km = meters / 1000
                return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
            }
        } else {
            let feet = meters * 3.28084
            if feet < 1000 {
                return "\(Int(feet)) ft"
            } else {
                let miles = meters / 1609.344
                return miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            ZStack {
                Circle()
                    .fill(Color.fromString(location.color).opacity(0.2))
                    .frame(width: 45, height: 45)

                Image(systemName: location.icon)
                    .font(.system(size: 20))
                    .foregroundColor(Color.fromString(location.color))
            }

            // Location Info
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    // Current Count with trend
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(location.currentCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        if location.comparison != "neutral" {
                            Text(location.comparisonSymbol)
                                .font(.subheadline)
                                .foregroundColor(location.comparisonColor)
                                .fontWeight(.bold)
                        }
                    }

                    // Overcrowding if available
                    if let overcrowding = location.overcrowding {
                        Text("Max: \(overcrowding)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Distance from user
                if let distance = distanceText {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(distance)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

