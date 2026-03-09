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
    @State private var showingFilterView = false
    @State private var selectedLocationId: String?
    @State private var showAdCarousel: Bool
    @State private var activeColorFilters: Set<String> = Set(MapColorCategory.allColorKeys)
    private var previewAds: [ServerAd]?
    private var previewLocations: [Location]?

    // TEMPORARY: Set to true to show demo ads for screenshots
    private static let useDemoAds = false

    init(showAds: Bool = true, previewAds: [ServerAd]? = nil, previewLocations: [Location]? = nil, initialColorFilter: Set<String>? = nil) {
        _showAdCarousel = State(initialValue: showAds)
        self.previewAds = Self.useDemoAds ? ServerAd.sampleAds : previewAds
        self.previewLocations = previewLocations
        if let filter = initialColorFilter {
            _activeColorFilters = State(initialValue: filter)
        }
    }

    private var isFilterActive: Bool {
        activeColorFilters.count < MapColorCategory.allColorKeys.count
    }

    private var displayLocations: [Location] {
        let base = previewLocations ?? viewModel.locations
        if isFilterActive {
            return base.filter { activeColorFilters.contains($0.color.lowercased()) }
        }
        return base
    }

    private var displayMapItems: [MapItem] {
        // In preview mode, show all locations as singles (no clustering)
        if let previewLocs = previewLocations {
            let filtered = isFilterActive ? previewLocs.filter { activeColorFilters.contains($0.color.lowercased()) } : previewLocs
            return filtered.map { .single($0) }
        }
        if !isFilterActive {
            return viewModel.mapItems
        }
        return viewModel.mapItems.compactMap { item in
            switch item {
            case .single(let location):
                return activeColorFilters.contains(location.color.lowercased()) ? item : nil
            case .cluster(let id, let coordinate, let locations):
                let filtered = locations.filter { activeColorFilters.contains($0.color.lowercased()) }
                if filtered.isEmpty { return nil }
                if filtered.count == 1 { return .single(filtered[0]) }
                return .cluster(id: id, coordinate: coordinate, locations: filtered)
            }
        }
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

    @MapContentBuilder
    private var mapContent: some MapContent {
        UserAnnotation()
        ForEach(displayMapItems) { item in
            switch item {
            case .single(let location):
                let tintColor: Color = location.color.lowercased() == "yellow"
                    ? Color(red: 0.82, green: 0.66, blue: 0.0)
                    : Color.fromString(location.color)
                Marker(location.name, systemImage: location.icon, coordinate: location.coordinate)
                    .tint(tintColor)
                    .tag(location.id)
            case .cluster(_, let coordinate, let locations):
                Annotation("", coordinate: coordinate) {
                    ClusterMarkerView(locations: locations)
                        .onTapGesture {
                            viewModel.zoomToFit(locations)
                        }
                }
            }
        }
    }

    var body: some View {
        ZStack {
            Map(position: $viewModel.cameraPosition, selection: $selectedLocationId) {
                mapContent
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { }
            .onMapCameraChange { context in
                // Detect if user has manually navigated (zoomed in from initial wide view)
                // Initial view has span ~50 degrees; if much smaller, user has navigated
                if !viewModel.userHasNavigated && !viewModel.hasSetInitialPosition {
                    let span = context.region.span
                    if span.latitudeDelta < 40 || span.longitudeDelta < 40 {
                        viewModel.userHasNavigated = true
                    }
                }

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

                // Update clustering based on zoom level
                if previewLocations == nil {
                    viewModel.scheduleClusterUpdate(for: context.region.span)
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
            .onChange(of: selectedLocationId) { _, newValue in
                if let locationId = newValue,
                   let location = displayLocations.first(where: { $0.id == locationId }) {
                    viewModel.centerOnLocation(location.coordinate)
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

            // Buttons, Ad Carousel, and Detail Card at bottom
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        RefreshButtonOverlay(viewModel: viewModel, adService: adService)
                        LocationButtonOverlay(viewModel: viewModel, locationManager: locationManager)
                        ListModeButtonOverlay(showingListView: $showingListView)
                        FilterButtonOverlay(showingFilterView: $showingFilterView, isFilterActive: isFilterActive)
                        ReportButtonOverlay()
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, {
                    let cardVisible = selectedLocationId != nil && displayLocations.contains(where: { $0.id == selectedLocationId })
                    let adVisible = showAdCarousel && !(previewAds ?? adService.activeAds).isEmpty
                    return cardVisible || adVisible ? 8 : 8 + bottomSafeAreaInset
                }())

                if let locationId = selectedLocationId,
                   let location = displayLocations.first(where: { $0.id == locationId }) {
                    LocationDetailCard(location: location) {
                        selectedLocationId = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showAdCarousel {
                    AdCarouselView(isVisible: $showAdCarousel, adService: adService, userLocation: locationManager.userLocation, locations: displayLocations, previewAds: previewAds)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: selectedLocationId)
            .edgesIgnoringSafeArea(.bottom)

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
            LocationListView(viewModel: viewModel, adService: adService, userLocation: locationManager.userLocation, onLocationSelected: { location in
                showingListView = false
                viewModel.centerOnLocation(location.coordinate)
                // Select the marker after a short delay so the sheet dismisses
                // and map centers before the detail card slides up
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    selectedLocationId = location.id
                }
            }, activeColorFilters: activeColorFilters)
        }
        .sheet(isPresented: $showingFilterView) {
            MapFilterView(activeFilters: $activeColorFilters)
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

// MARK: - MapItem

enum MapItem: Identifiable {
    case single(Location)
    case cluster(id: String, coordinate: CLLocationCoordinate2D, locations: [Location])

    var id: String {
        switch self {
        case .single(let location):
            return location.id
        case .cluster(let id, _, _):
            return id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let location):
            return location.coordinate
        case .cluster(_, let coordinate, _):
            return coordinate
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
    @Published var userHasNavigated = false  // Track if user has manually navigated the map
    @Published private(set) var mapItems: [MapItem] = []
    private var lastClusteredSpan: MKCoordinateSpan?
    private var clusterDebounceWork: DispatchWorkItem?

    init() {
        refreshLocations()
    }

    func centerOnUserLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            )
            isMapCenteredOnUser = true
        }
    }

    func centerOnLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
                )
            )
        }
    }

    /// Zoom to fit a set of locations (e.g. from a tapped cluster)
    func zoomToFit(_ locations: [Location]) {
        guard !locations.isEmpty else { return }
        var minLat = locations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = locations[0].coordinate.longitude
        var maxLon = minLon
        for loc in locations {
            minLat = min(minLat, loc.coordinate.latitude)
            maxLat = max(maxLat, loc.coordinate.latitude)
            minLon = min(minLon, loc.coordinate.longitude)
            maxLon = max(maxLon, loc.coordinate.longitude)
        }
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = max((maxLat - minLat) * 1.5, 0.005)
        let spanLon = max((maxLon - minLon) * 1.5, 0.005)
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
                )
            )
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
        guard !userHasNavigated else {
            hasSetInitialPosition = true  // Mark as set so we don't keep trying
            return
        }
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
                guard let locationId = location["location_id"] as? String,
                      let name = location["location_name"] as? String,
                      let latitude = location["location_latitude"] as? Double,
                      let longitude = location["location_longitude"] as? Double,
                      let color = location["location_color"] as? String,
                      let icon = location["location_icon"] as? String,
                      let currentCount = location["current_count"] as? Int else {
                    continue
                }

                // Parse devices array: [[device_id, label], ...]
                var deviceIds: [String] = []
                if let devices = location["devices"] as? [[Any]] {
                    deviceIds = devices.compactMap { $0.first as? String }
                }

                // Parse overcrowding limit
                var overcrowding: Int? = nil
                if let overcrowdingValue = location["overcrowding_limit"] {
                    if let overcrowdingInt = overcrowdingValue as? Int {
                        overcrowding = overcrowdingInt
                    } else if let overcrowdingStr = overcrowdingValue as? String,
                                  let overcrowdingInt = Int(overcrowdingStr) {
                        overcrowding = overcrowdingInt
                    }
                }

                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

                // Parse comparison trend
                let comparison = location["location_comparison"] as? String ?? "neutral"

                // Parse closed state
                let isClosed = location["is_closed"] as? Bool ?? false

                // Only add if we haven't seen this ID before
                if !seenIds.contains(locationId) {
                    seenIds.insert(locationId)
                    let newLocation = Location(
                        id: locationId,
                        name: name,
                        coordinate: coordinate,
                        deviceIds: deviceIds,
                        color: color,
                        icon: icon,
                        currentCount: currentCount,
                        isClosed: isClosed,
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
                self.updateClusters(for: self.lastClusteredSpan)
            }
        }
    }

    func updateClusters(for span: MKCoordinateSpan?) {
        let span = span ?? MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)

        // Skip recomputation if span hasn't changed by >10%
        if let last = lastClusteredSpan, !mapItems.isEmpty {
            let latRatio = abs(span.latitudeDelta - last.latitudeDelta) / max(last.latitudeDelta, 0.001)
            let lonRatio = abs(span.longitudeDelta - last.longitudeDelta) / max(last.longitudeDelta, 0.001)
            if latRatio < 0.1 && lonRatio < 0.1 {
                return
            }
        }

        lastClusteredSpan = span

        // Zoomed in enough → show all as singles
        if span.latitudeDelta < 0.5 {
            mapItems = locations.map { .single($0) }
            return
        }

        // Distance-based clustering: merge any locations within radius of each other
        let clusterRadius = span.latitudeDelta * 0.15
        var assigned = [Bool](repeating: false, count: locations.count)
        var items: [MapItem] = []

        for i in 0..<locations.count {
            guard !assigned[i] else { continue }
            assigned[i] = true

            // Seed a cluster from this location
            var group = [locations[i]]
            var centerLat = locations[i].coordinate.latitude
            var centerLon = locations[i].coordinate.longitude

            // Pull in all unassigned locations within radius of the running center
            var changed = true
            while changed {
                changed = false
                for j in 0..<locations.count {
                    guard !assigned[j] else { continue }
                    let loc = locations[j]
                    let avgLat = centerLat / Double(group.count)
                    let avgLon = centerLon / Double(group.count)
                    let dLat = loc.coordinate.latitude - avgLat
                    let dLon = loc.coordinate.longitude - avgLon
                    if dLat * dLat + dLon * dLon <= clusterRadius * clusterRadius {
                        assigned[j] = true
                        group.append(loc)
                        centerLat += loc.coordinate.latitude
                        centerLon += loc.coordinate.longitude
                        changed = true
                    }
                }
            }

            if group.count == 1 {
                items.append(.single(group[0]))
            } else {
                let avgLat = centerLat / Double(group.count)
                let avgLon = centerLon / Double(group.count)
                let coord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
                items.append(.cluster(id: "cluster_\(i)", coordinate: coord, locations: group))
            }
        }

        mapItems = items
    }

    func scheduleClusterUpdate(for span: MKCoordinateSpan) {
        clusterDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.updateClusters(for: span)
            }
        }
        clusterDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

// MARK: - Location Model

struct Location: Identifiable {
    let id: String          // Server location_id (UUID)
    let name: String
    let coordinate: CLLocationCoordinate2D
    let deviceIds: [String] // All device IDs in this location
    let color: String
    let icon: String
    let currentCount: Int
    let isClosed: Bool
    let comparison: String  // "up", "down", or "neutral"
    let overcrowding: Int?

    var comparisonSymbol: String {
        switch comparison {
        case "up": return "↑"
        case "down": return "↓"
        default: return ""
        }
    }

    var comparisonColor: Color {
        switch comparison {
        case "up": return .green
        case "down": return .red
        default: return .gray
        }
    }

    /// Whether this location contains the given device ID (used for ad matching)
    func containsDevice(_ deviceId: String) -> Bool {
        deviceIds.contains(deviceId)
    }

    // Sample locations for previews (Boulder, CO area)
    static let sampleLocations: [Location] = [
        Location(
            id: "sample-1",
            name: "CrowdCount HQ",
            coordinate: CLLocationCoordinate2D(latitude: 40.0192959, longitude: -105.28284905),
            deviceIds: ["T0001"],
            color: "red",
            icon: "flag.2.crossed.fill",
            currentCount: 5,
            isClosed: false,
            comparison: "up",
            overcrowding: 10
        ),
        Location(
            id: "sample-2",
            name: "City Park",
            coordinate: CLLocationCoordinate2D(latitude: 40.01783, longitude: -105.2684),
            deviceIds: ["T0002"],
            color: "green",
            icon: "tree.fill",
            currentCount: 23,
            isClosed: false,
            comparison: "down",
            overcrowding: nil
        ),
        Location(
            id: "sample-3",
            name: "The Pond",
            coordinate: CLLocationCoordinate2D(latitude: 40.00087, longitude: -105.25944),
            deviceIds: ["T0000"],
            color: "blue",
            icon: "fish.fill",
            currentCount: 29,
            isClosed: false,
            comparison: "neutral",
            overcrowding: nil
        ),
        Location(
            id: "sample-4",
            name: "McCrowd's Pub",
            coordinate: CLLocationCoordinate2D(latitude: 40.00846, longitude: -105.27546),
            deviceIds: ["Demo"],
            color: "orange",
            icon: "mug.fill",
            currentCount: 86,
            isClosed: false,
            comparison: "up",
            overcrowding: 100
        )
    ]
}

// MARK: - FadeInView

private struct FadeInView<Content: View>: View {
    let content: Content
    @State private var visible = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            .animation(.easeOut(duration: 0.25), value: visible)
            .onAppear { visible = true }
    }
}

// MARK: - ClusterMarkerView

private struct ClusterMarkerView: View {
    let locations: [Location]

    private var locationCount: Int { locations.count }
    private var totalPeople: Int { locations.reduce(0) { $0 + $1.currentCount } }

    // Scale circle size from 36pt (2 locations) to 60pt (10+ locations)
    private var circleSize: CGFloat {
        let minSize: CGFloat = 36
        let maxSize: CGFloat = 60
        let t = min(Double(locationCount - 2) / 8.0, 1.0)
        return minSize + CGFloat(t) * (maxSize - minSize)
    }

    @State private var visible = false

    var body: some View {
        VStack(spacing: 1) {
            Text("\(locationCount)")
                .font(.system(size: 15, weight: .bold))
            Text("\(totalPeople)")
                .font(.system(size: 10))
                .opacity(0.85)
        }
        .frame(width: circleSize, height: circleSize)
        .background(
            Circle()
                .fill(Color.blue)
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        )
        .foregroundColor(.white)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.3)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: visible)
        .onAppear { visible = true }
    }
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
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(self.colorScheme == .dark ? .white : .primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "magnifyingglass")
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

// MARK: - MapColorCategory

struct MapColorCategory: Identifiable {
    let id: String      // color key (lowercased)
    let color: Color
    let label: String

    static let all: [MapColorCategory] = [
        MapColorCategory(id: "red", color: .red, label: "General"),
        MapColorCategory(id: "orange", color: .orange, label: "Restaurants & Bars"),
        MapColorCategory(id: "yellow", color: Color(red: 0.88, green: 0.72, blue: 0.0), label: "Grocery & Market"),
        MapColorCategory(id: "green", color: .green, label: "Fashion & Accessories"),
        MapColorCategory(id: "blue", color: .blue, label: "Retail & Home Goods"),
        MapColorCategory(id: "purple", color: .purple, label: "Government & Organizations"),
        MapColorCategory(id: "pink", color: Color(red: 1.0, green: 0.2, blue: 0.55), label: "Entertainment & Venues"),
    ]

    static let allColorKeys: [String] = all.map { $0.id }
}

// MARK: - FilterButtonOverlay

private struct FilterButtonOverlay: View {
    @Binding var showingFilterView: Bool
    var isFilterActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { showingFilterView = true }) {
            if #available(iOS 26.0, *) {
                Image(systemName: "list.bullet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(isFilterActive ? .blue : (colorScheme == .dark ? .white : .primary))
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "list.bullet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(isFilterActive ? .blue : .primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - MapFilterView

struct MapFilterView: View {
    @Binding var activeFilters: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var allEnabled: Bool {
        activeFilters.count == MapColorCategory.allColorKeys.count
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(MapColorCategory.all) { category in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if activeFilters.contains(category.id) {
                                    activeFilters.remove(category.id)
                                } else {
                                    activeFilters.insert(category.id)
                                }
                            }
                        } label: {
                            let isSelected = activeFilters.contains(category.id)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? category.color : .clear)
                                        .frame(width: 32, height: 32)
                                    Circle()
                                        .strokeBorder(category.color, lineWidth: 2.5)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .scaleEffect(isSelected ? 1 : 0.01)
                                        .opacity(isSelected ? 1 : 0)
                                }

                                Text(category.label)
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                        }
                    }
                }

                Section {
                    Button(allEnabled ? "Deselect All" : "Select All") {
                        if allEnabled {
                            activeFilters.removeAll()
                        } else {
                            activeFilters = Set(MapColorCategory.allColorKeys)
                        }
                    }
                }
            }
            .navigationTitle("Filter by Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
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

// MARK: - LocationDetailCard

private struct LocationDetailCard: View {
    let location: Location
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var popularTimesData: PopularTimesData?
    @State private var isLoadingPopularTimes = false
    @State private var chartCurrentCount: Int = 0
    @State private var chartIsClosed: Bool = true
    @State private var isCollapsingChart = false

    private var pinColor: Color {
        location.color.lowercased() == "yellow"
            ? Color(red: 0.82, green: 0.66, blue: 0.0)
            : Color.fromString(location.color)
    }

    private var cardContent: some View {
        VStack(spacing: 16) {
            // Header row: icon circle, name, dismiss button
            HStack {
                ZStack {
                    Circle()
                        .fill(pinColor)
                        .overlay(colorScheme == .dark && location.color.lowercased() != "yellow" ? Circle().fill(.black.opacity(0.1)) : nil)
                        .frame(width: 36, height: 36)
                    Image(systemName: location.icon)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }

                Text(location.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            // Bottom section: count/stats on left, directions button bottom right
            HStack(alignment: .bottom) {
                // Left side: count, trend, overcrowding
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current count")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if location.isClosed {
                        Text("Closed")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let overcrowding = location.overcrowding {
                                Text("\(location.currentCount)")
                                    .font(.system(size: 48, weight: .bold))
                                Text("/")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("\(overcrowding)")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(location.currentCount)")
                                    .font(.system(size: 48, weight: .bold))
                            }

                            if location.comparison != "neutral" {
                                Text(location.comparisonSymbol)
                                    .font(.title)
                                    .foregroundColor(location.comparisonColor)
                            }
                        }
                    }
                }

                Spacer()

                // Right side: Get Directions button
                Button(action: {
                    let placemark = MKPlacemark(coordinate: location.coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = location.name
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                }) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(
                            Capsule().fill(pinColor)
                                .overlay(colorScheme == .dark && location.color.lowercased() != "yellow" ? Capsule().fill(.black.opacity(0.1)) : nil)
                        )
                }
            }

            // Popular Times chart
            VStack {
                if popularTimesData == nil && isLoadingPopularTimes {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 150)
                        .redacted(reason: .placeholder)
                } else if let data = popularTimesData, !data.hourlyAverages.isEmpty {
                    PopularTimesChart(data: data, accentColor: pinColor, currentCount: chartCurrentCount, isClosed: chartIsClosed)
                        .frame(height: isCollapsingChart ? 0 : nil, alignment: .top)
                        .clipped()
                } else if !isLoadingPopularTimes && popularTimesData == nil {
                    Text("Popular times will appear after this location has been active for at least a week.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .transition(.opacity.animation(.easeIn(duration: 0.15)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 40)
        .task(id: location.id) {
            // First load only: show skeleton while old chart stays visible on switch
            if popularTimesData == nil {
                isLoadingPopularTimes = true
            }
            do {
                let result = try await APIService.shared.fetchPopularTimes(locationId: location.id)
                let hasData = result != nil && !(result?.hourlyAverages.isEmpty ?? true)
                if hasData {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        popularTimesData = result
                        chartCurrentCount = location.currentCount
                        chartIsClosed = location.isClosed
                        isLoadingPopularTimes = false
                        isCollapsingChart = false
                    }
                } else {
                    // Animate bars to zero + collapse height simultaneously
                    if popularTimesData != nil {
                        let zeroed = PopularTimesData(
                            hourlyAveragesUTC: Dictionary(uniqueKeysWithValues: (0..<24).map { (String($0), 0.0) }),
                            dayOfWeek: ""
                        )
                        withAnimation(.easeInOut(duration: 0.3)) {
                            popularTimesData = zeroed
                            chartCurrentCount = 0
                            chartIsClosed = true
                            isCollapsingChart = true
                        }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    popularTimesData = nil
                    isCollapsingChart = false
                    isLoadingPopularTimes = false
                }
            } catch {
                if popularTimesData != nil {
                    let zeroed = PopularTimesData(
                        hourlyAveragesUTC: Dictionary(uniqueKeysWithValues: (0..<24).map { (String($0), 0.0) }),
                        dayOfWeek: ""
                    )
                    withAnimation(.easeInOut(duration: 0.3)) {
                        popularTimesData = zeroed
                        chartCurrentCount = 0
                        chartIsClosed = true
                        isCollapsingChart = true
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                popularTimesData = nil
                isCollapsingChart = false
                isLoadingPopularTimes = false
            }
        }
    }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous)
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            cardContent
                .glassEffect(.regular, in: cardShape)
        } else {
            cardContent
                .background(
                    cardShape
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -4)
                )
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

