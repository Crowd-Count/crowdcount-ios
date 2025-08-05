import SwiftUI
import MapKit

// MARK: - MapContentView

struct MapContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        ZStack {
            Map {
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
//                                        .offset(x: -8)
                                }
                                if let overcrowding = location.overcrowding {
                                    Text(" / \(overcrowding)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
//                                        .offset(x: -8)
                                }
                            }
                            .offset(y: -2)
                        }
                        .shadow(color: appSettings.isDarkMode ? .black : .white, radius: 1)
                        .offset(y: 16)
                    }
                }
            }
            .onAppear {
                viewModel.refreshLocations()
            }
            .edgesIgnoringSafeArea(.all)
            .navigationBarTitle("CrowdCount Map", displayMode: .inline)
            
            ButtonOverlay(viewModel: viewModel)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
            }
        }
    }
}

// MARK: - MapViewModel

@MainActor
class MapViewModel: ObservableObject {
    @Published var locations = [Location]()
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.01833, longitude: -105.28202),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )
    @Published var isLoading = true

    init() {
        refreshLocations()
    }

    func fetchLocations() async -> [[String: Any]] {
        guard let url = URL(string: "https://crowdcount.tech/api/get_all_location_data_with_extra") else {
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
        locations.removeAll()
        Task {
            let fetchedLocations = await fetchLocations()
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
                let newLocation = Location(
                    name: name,
                    coordinate: coordinate,
                    userId: userId,
                    color: color,
                    icon: icon,
                    currentCount: currentCount,
                    comparison: comparison,
                    overcrowding: overcrowding // Include the new property
                )
                await MainActor.run {
                    self.locations.append(newLocation)
                }
            }
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Location Model

struct Location: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let userId: String
    let color: String
    let icon: String
    let currentCount: Int
    let comparison: String
    let overcrowding: Int? // New property to hold overcrowding number

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

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    RefreshButtonOverlay(viewModel: viewModel)
                    InfoButtonOverlay()
                    ReportButtonOverlay()
                }
            }
            .padding(.trailing, 20)
        }
        .padding(.bottom, 10)
    }
}

// MARK: - RefreshButtonOverlay

private struct RefreshButtonOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var isAnimating = false

    var body: some View {
        Button(action: {
            viewModel.refreshLocations()
        }) {
            if #available(iOS 26.0, *) {
                Image(systemName: "arrow.clockwise")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundColor(.primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect()
            } else {
                Image(systemName: "arrow.clockwise")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
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
                    .frame(width: 25, height: 25)
                    .foregroundColor(.red)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect()
            } else {
                Image(systemName: "exclamationmark.bubble.fill")
                    .resizable()
                    .frame(width: 25, height: 25)
                    .foregroundColor(.white)
                    .padding()
                    .background(.red)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}

// MARK: - InfoButtonOverlay

private struct InfoButtonOverlay: View {
    var body: some View {
        NavigationLink(destination: InfoMapView()) {
            if #available(iOS 26.0, *) {
                Image(systemName: "info")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundColor(.primary)
                    .padding()
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .glassEffect()
            } else {
                Image(systemName: "info")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundColor(.primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 10)
            }
        }
    }
}
