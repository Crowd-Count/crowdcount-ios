import SwiftUI
import MapKit
import CoreLocation

// MARK: - MapContentView

struct MapContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingListView = false

    var body: some View {
        ZStack {
            Map(position: $viewModel.cameraPosition) {
                ForEach(viewModel.locations) { location in
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
                viewModel.refreshLocations()
                locationManager.requestLocationPermission()
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
            
            ButtonOverlay(
                viewModel: viewModel,
                locationManager: locationManager,
                isMapCenteredOnUser: $viewModel.isMapCenteredOnUser,
                showingListView: $showingListView
            )
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
            }
        }
        .sheet(isPresented: $showingListView) {
            LocationListView(viewModel: viewModel)
        }
    }
}

// MARK: - LocationManager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            DispatchQueue.main.async {
                self.userLocation = location.coordinate
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

// MARK: - MapViewModel

@MainActor
class MapViewModel: ObservableObject {
    @Published var locations = [Location]()
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.010483, longitude: -105.271124),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    )
    @Published var isLoading = true
    @Published var isMapCenteredOnUser = false

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
        }
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
}

// MARK: - ButtonOverlay

private struct ButtonOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject var locationManager: LocationManager
    @Binding var isMapCenteredOnUser: Bool
    @Binding var showingListView: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 5) {
                    RefreshButtonOverlay(viewModel: viewModel)
                    LocationButtonOverlay(viewModel: viewModel, locationManager: locationManager)
                    ListModeButtonOverlay(showingListView: $showingListView)
                    ReportButtonOverlay()
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.bottom, 0)
    }
}

// MARK: - RefreshButtonOverlay

private struct RefreshButtonOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            viewModel.refreshLocations()
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
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
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
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
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
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
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
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
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

