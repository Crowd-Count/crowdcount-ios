import SwiftUI
import MapKit
import CoreLocation

// MARK: - MapContentView

struct MapContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var adService = AdService()
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingListView = false
    @State private var showAdCarousel: Bool
    private var previewAds: [ServerAd]?
    private var previewLocations: [Location]?

    // TEMPORARY: Set to true to show demo ads for screenshots
    private static let useDemoAds = false

    init(showAds: Bool = true, previewAds: [ServerAd]? = nil, previewLocations: [Location]? = nil) {
        _showAdCarousel = State(initialValue: showAds)
        self.previewAds = Self.useDemoAds ? ServerAd.sampleAds : previewAds
        self.previewLocations = previewLocations
    }

    private var displayLocations: [Location] {
        previewLocations ?? viewModel.locations
    }

    // Get the bottom safe area inset
    private var bottomSafeAreaInset: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window.safeAreaInsets.bottom
        }
        return 0
    }

    // Bottom padding for ad carousel: 8pt from the absolute bottom of the screen
    private var adCarouselBottomPadding: CGFloat {
        8 - bottomSafeAreaInset
    }

    // Helper to compare coordinates with a small tolerance
    private func coordsEqual(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?, epsilon: Double = 1e-6) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            return abs(lhs.latitude - rhs.latitude) < epsilon && abs(lhs.longitude - rhs.longitude) < epsilon
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            Map(position: $viewModel.cameraPosition) {
                ForEach(displayLocations) { location in
                    Marker(location.name, systemImage: location.icon, coordinate: location.coordinate)
                        .tint(Color.fromString(location.color))
                    Annotation("", coordinate: location.coordinate) {
                        VStack {
                            Text("\(location.name)")
                                .font(.caption)
                                .bold()
                            HStack(spacing: 0) {
                                Text("Count: \(location.currentCount)")
                                    .font(.caption)
                                if location.comparison != "neutral" {
                                    Text(location.comparisonSymbol)
                                        .font(.caption)
                                        .foregroundColor(location.comparisonColor)
                                }
                                if let overcrowding = location.overcrowding {
                                    Text(" / \(overcrowding)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .offset(y: -2)
                        }
                        .shadow(color: appSettings.isDarkMode ? .black : .white, radius: 1)
                        .offset(y: 16)
                    }
                }
            }
            .onMapCameraChange { context in
                // Check if map is still centered on user location
                if let userLocation = locationManager.userLocation {
                    let mapCenter = context.region.center
                    let distance = CLLocation(
                        latitude: mapCenter.latitude,
                        longitude: mapCenter.longitude
                    ).distance(from: CLLocation(
                        latitude: userLocation.latitude,
                        longitude: userLocation.longitude
                    ))
                    // If moved more than 100 meters from user location, unfill the icon
                    viewModel.isMapCenteredOnUser = distance < 100
                } else {
                    viewModel.isMapCenteredOnUser = false
                }
            }
            .onAppear {
                // If using preview locations, set camera to fit them
                if let previewLocs = previewLocations, !previewLocs.isEmpty {
                    // Calculate center of preview locations
                    let lats = previewLocs.map { $0.coordinate.latitude }
                    let lons = previewLocs.map { $0.coordinate.longitude }
                    let centerLat = (lats.min()! + lats.max()!) / 2
                    let centerLon = (lons.min()! + lons.max()!) / 2
                    let spanLat = (lats.max()! - lats.min()!) * 1.5
                    let spanLon = (lons.max()! - lons.min()!) * 1.5
                    viewModel.cameraPosition = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                            span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.02), longitudeDelta: max(spanLon, 0.02))
                        )
                    )
                    viewModel.isLoading = false
                } else {
                    viewModel.refreshLocations()
                    locationManager.requestLocationPermission()

                    // If authorization was already determined before view appeared, check status
                    if locationManager.authorizationStatus == .authorizedWhenInUse ||
                       locationManager.authorizationStatus == .authorizedAlways {
                        locationManager.requestLocation()
                    } else if locationManager.authorizationStatus == .denied ||
                              locationManager.authorizationStatus == .restricted {
                        locationManager.locationDetermined = true
                    }

                    // Timeout fallback: if we don't get location within 5 seconds, fit all markers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        if !viewModel.hasSetInitialPosition && !viewModel.isLoading {
                            viewModel.setInitialPosition(userLocation: locationManager.userLocation)
                        }
                    }
                }
            }
            // Set initial position when we have location info and locations are loaded
            .onChange(of: locationManager.locationDetermined) { _, determined in
                if determined && !viewModel.isLoading {
                    viewModel.setInitialPosition(userLocation: locationManager.userLocation)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if !isLoading && locationManager.locationDetermined {
                    viewModel.setInitialPosition(userLocation: locationManager.userLocation)
                }
            }
            // Also handle when user location becomes available
            .onReceive(locationManager.objectWillChange) { _ in
                // When userLocation becomes available and initial position hasn't been set
                if !viewModel.hasSetInitialPosition, let newLocation = locationManager.userLocation, !viewModel.isLoading {
                    viewModel.setInitialPosition(userLocation: newLocation)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .navigationBarTitle("CrowdCount Map", displayMode: .inline)
            .navigationBarItems(trailing:
                NavigationLink(destination: InfoMapView()) {
                if #available(iOS 26.0, *) {
                    Image(systemName: "info")
                        .foregroundColor(self.colorScheme == .dark ? .white : .primary)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.primary)
                }
                }
            )

            // Buttons and Ad Carousel at bottom
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        RefreshButtonOverlay(viewModel: viewModel, adService: adService)
                        LocationButtonOverlay(viewModel: viewModel, locationManager: locationManager)
                        ListModeButtonOverlay(showingListView: $showingListView)
                        ReportButtonOverlay()
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)

                if showAdCarousel {
                    AdCarouselView(isVisible: $showAdCarousel, adService: adService, userLocation: locationManager.userLocation, locations: displayLocations, previewAds: previewAds)
                        .padding(.horizontal, 8)
                        .padding(.bottom, adCarouselBottomPadding)
                }
            }

            if viewModel.isLoading {
                if #available(iOS 26.0, *) {
                    ProgressView()
                        .frame(width: 80, height: 80)
                        .cornerRadius(20)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                } else {
                    ProgressView()
                        .frame(width: 80, height: 80)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                }
            }
        }
        .sheet(isPresented: $showingListView) {
            LocationListView(viewModel: viewModel, adService: adService)
        }
    }
}

// MARK: - LocationManager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationDetermined = false  // True once we know if we can get location or not

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            DispatchQueue.main.async {
                self.userLocation = location.coordinate
                self.locationDetermined = true
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.locationDetermined = true  // Mark as determined even on failure
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus

            // If authorization changed to authorized, start getting location
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.locationDetermined = true  // Can't get location, mark as determined
            case .notDetermined:
                break  // Still waiting for user decision
            @unknown default:
                break
            }
        }
    }
}

// MARK: - MapViewModel

@MainActor
class MapViewModel: ObservableObject {
    @Published var locations = [Location]()
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of USA as initial
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50) // Wide view initially
        )
    )
    @Published var isLoading = true
    @Published var isMapCenteredOnUser = false
    @Published var hasSetInitialPosition = false  // Track if we've set the initial map position

    init() {
        refreshLocations()
    }

    func centerOnUserLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
            isMapCenteredOnUser = true
        }
    }

    /// Fit all location markers in the map view
    func fitAllMarkers() {
        guard !locations.isEmpty else { return }

        // Calculate the bounding box of all locations
        var minLat = locations[0].coordinate.latitude
        var maxLat = locations[0].coordinate.latitude
        var minLon = locations[0].coordinate.longitude
        var maxLon = locations[0].coordinate.longitude

        for location in locations {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }

        // Calculate center and span with some padding
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.5  // 50% padding
        let spanLon = (maxLon - minLon) * 1.5

        // Ensure minimum span so we don't zoom in too much for single/close markers
        let finalSpanLat = max(spanLat, 0.01)
        let finalSpanLon = max(spanLon, 0.01)

        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: finalSpanLat, longitudeDelta: finalSpanLon)
                )
            )
        }
    }

    /// Set initial map position based on user location or fall back to fitting all markers
    func setInitialPosition(userLocation: CLLocationCoordinate2D?) {
        guard !hasSetInitialPosition else { return }
        hasSetInitialPosition = true

        if let userLocation = userLocation {
            centerOnUserLocation(userLocation)
        } else if !locations.isEmpty {
            fitAllMarkers()
        }
        // If no user location and no markers, keep the default USA-wide view
    }

    func fetchLocations() async -> [[String: Any]] {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_all_location_data_with_extra") else {
            return []
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return []
            }
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return json?["locations"] as? [[String: Any]] ?? []
        } catch {
            print("Error fetching locations: \(error)")
            return []
        }
    }

    func refreshLocations() {
        isLoading = true
        Task {
            // Clear locations on the main thread
            await MainActor.run {
                self.locations.removeAll()
            }
            
            let fetchedLocations = await fetchLocations()
            var uniqueLocations = [Location]()
            var seenIds = Set<String>()
            
            for location in fetchedLocations {
                guard let name = location["location_name"] as? String,
                      let latitude = location["location_latitude"] as? Double,
                      let longitude = location["location_longitude"] as? Double,
                      let userId = location["location_device"] as? String,
                      let color = location["location_color"] as? String,
                      let icon = location["location_icon"] as? String,
                      let currentCount = location["location_current_count"] as? Int,
                      let comparison = location["location_comparison"] as? String else {
                    continue
                }

                // Parsing the overcrowding value
                var overcrowding: Int? = nil
                if let overcrowdingValue = location["location_overcrowding_count"] {
                    if let overcrowdingInt = overcrowdingValue as? Int {
                        overcrowding = overcrowdingInt
                    } else if let overcrowdingStr = overcrowdingValue as? String,
                                  let overcrowdingInt = Int(overcrowdingStr) {
                        overcrowding = overcrowdingInt
                    }
                }

                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                let locationId = userId + "_" + name
                
                // Only add if we haven't seen this ID before
                if !seenIds.contains(locationId) {
                    seenIds.insert(locationId)
                    let newLocation = Location(
                        id: locationId,
                        name: name,
                        coordinate: coordinate,
                        userId: userId,
                        color: color,
                        icon: icon,
                        currentCount: currentCount,
                        comparison: comparison,
                        overcrowding: overcrowding
                    )
                    uniqueLocations.append(newLocation)
                }
            }
            
            // Update locations array on main thread
            await MainActor.run {
                self.locations = uniqueLocations
                self.isLoading = false
            }
        }
    }
}

// MARK: - Location Model

struct Location: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let userId: String
    let color: String
    let icon: String
    let currentCount: Int
    let comparison: String
    let overcrowding: Int?

    var comparisonSymbol: String {
        switch comparison {
        case "up":
            return "↑"
        case "down":
            return "↓"
        case "neutral":
            return ""
        default:
            return ""
        }
    }

    var comparisonColor: Color {
        switch comparison {
        case "up":
            return .green
        case "down":
            return .red
        case "neutral":
            return .gray
        default:
            return .gray
        }
    }

    // Sample locations for previews (Boulder, CO area)
    static let sampleLocations: [Location] = [
        Location(
            id: "sample-1",
            name: "CrowdCount HQ",
            coordinate: CLLocationCoordinate2D(latitude: 40.0192959, longitude: -105.28284905),
            userId: "T0001",
            color: "red",
            icon: "flag.2.crossed.fill",
            currentCount: 5,
            comparison: "up",
            overcrowding: 10
        ),
        Location(
            id: "sample-2",
            name: "City Park",
            coordinate: CLLocationCoordinate2D(latitude: 40.01783, longitude: -105.2684),
            userId: "T0002",
            color: "green",
            icon: "tree.fill",
            currentCount: 23,
            comparison: "neutral",
            overcrowding: nil
        ),
        Location(
            id: "sample-3",
            name: "The Pond",
            coordinate: CLLocationCoordinate2D(latitude: 40.00087, longitude: -105.25944),
            userId: "T0000",
            color: "blue",
            icon: "fish.fill",
            currentCount: 29,
            comparison: "down",
            overcrowding: nil
        ),
        Location(
            id: "sample-4",
            name: "McCrowd's Pub",
            coordinate: CLLocationCoordinate2D(latitude: 40.00846, longitude: -105.27546),
            userId: "Demo",
            color: "orange",
            icon: "mug.fill",
            currentCount: 86,
            comparison: "up",
            overcrowding: 100
        )
    ]
}

// MARK: - RefreshButtonOverlay

private struct RefreshButtonOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject var adService: AdService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            viewModel.refreshLocations()
            Task {
                await adService.fetchActiveAds()
            }
        }) {
            if #available(iOS 26.0, *) {
                Image(systemName: "arrow.clockwise")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(self.colorScheme == .dark ? .white : .primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "arrow.clockwise")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - ListModeButtonOverlay

private struct ListModeButtonOverlay: View {
    @Binding var showingListView: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            showingListView = true
        }) {
            if #available(iOS 26.0, *) {
                Image(systemName: "list.bullet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(self.colorScheme == .dark ? .white : .primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "list.bullet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - ReportButtonOverlay

private struct ReportButtonOverlay: View {
    var body: some View {
        NavigationLink(destination: ReportContentView()) {
            if #available(iOS 26.0, *) {
                Image(systemName: "exclamationmark.bubble")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.red)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "exclamationmark.bubble.fill")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
                    .padding()
                    .background(.red)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - LocationButtonOverlay

private struct LocationButtonOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            // First request location
            locationManager.requestLocation()

            // Then center the map with a delay to allow location to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let userLocation = locationManager.userLocation {
                    viewModel.centerOnUserLocation(userLocation)
                    viewModel.isMapCenteredOnUser = true
                } else {
                    // If still no location, request it again
                    locationManager.requestLocation()
                    // Try centering again after another delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let userLocation = locationManager.userLocation {
                            viewModel.centerOnUserLocation(userLocation)
                            viewModel.isMapCenteredOnUser = true
                        }
                    }
                }
            }
        }) {
            if #available(iOS 26.0, *) {
                Image(systemName: viewModel.isMapCenteredOnUser ? "location.fill" : "location")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(self.colorScheme == .dark ? .white : .primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(),in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: viewModel.isMapCenteredOnUser ? "location.fill" : "location")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - Preview

#Preview("Map with Locations & Ads") {
    NavigationStack {
        MapContentView(
            showAds: true,
            previewAds: ServerAd.sampleAds,
            previewLocations: Location.sampleLocations
        )
        .environmentObject(AppSettings())
    }
    .preferredColorScheme(.dark)
}

#Preview("Map with Locations & Ads - Light") {
    NavigationStack {
        MapContentView(
            showAds: true,
            previewAds: ServerAd.sampleAds,
            previewLocations: Location.sampleLocations
        )
        .environmentObject(AppSettings())
    }
    .preferredColorScheme(.light)
}

#Preview("Map without Ad Carousel") {
    NavigationStack {
        MapContentView(showAds: false, previewLocations: Location.sampleLocations)
            .environmentObject(AppSettings())
    }
    .preferredColorScheme(.dark)
}

