import SwiftUI

struct TotalCountView: View {
    let totalCount: Int
    let totalOvercrowdingCount: Int
    let users: [User]
    @Binding var userPasswords: [UUID: String]
    let locationName: String
    @ObservedObject var alertViewModel: AlertViewModel
    let serverURL: String
    let onLocationMapStatusChanged: (Bool) -> Void  // Callback when map status changes
    let onMapDataFetched: ([String: String], [String: String]) -> Void  // Callback with (deviceLocationNames, devicePrimaryDevices)
    let isBluetoothSetupRequired: [UUID: Bool]  // Offline status for each device

    @Environment(\.colorScheme) var colorScheme

    // Map status state
    @State private var isLocationOnMap: Bool = false
    @State private var deviceLocationNames: [String: String] = [:]
    @State private var devicePrimaryDevices: [String: String] = [:]
    @State private var showDemoAdAlert: Bool = false

    // Check if this location has a demo device
    private var hasDemoDevice: Bool {
        users.contains { $0.userId == "Demo" }
    }

    // Devices in this location that are NOT on the map
    private var extraDevices: [User] {
        guard isLocationOnMap else { return [] }
        return users.filter { !deviceLocationNames.keys.contains($0.userId) && $0.userId != "Demo" }
    }

    // Device IDs that belong to this map location but are NOT in the app
    private var missingMapDevices: [String] {
        guard isLocationOnMap else { return [] }
        let userDeviceIds = Set(users.map { $0.userId })
        // Find all devices that belong to this location name on the map
        let mapDevicesForThisLocation = deviceLocationNames.filter { $0.value == locationName }.map { $0.key }
        // Return ones not in the app
        return mapDevicesForThisLocation.filter { !userDeviceIds.contains($0) }
    }

    // Counters that are offline (need Bluetooth setup / not connected to WiFi)
    private var offlineCounters: [User] {
        users.filter { isBluetoothSetupRequired[$0.id] == true }
    }

    var body: some View {
        VStack {
            Spacer()
            Spacer()
            VStack(spacing: 4) {
                Text("Total Count for")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(locationName)
                    .font(.title)
                    .fontWeight(.semibold)
            }
            .padding(.top)

            Group {
                if totalOvercrowdingCount > 0 {
                    Text("\(totalCount)")
                        .fontWeight(.bold)
                    + Text(" / \(totalOvercrowdingCount)")
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(totalCount)")
                        .fontWeight(.bold)
                }
            }
            .font(.system(size: 75))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            NavigationLink(destination: AggregatedHistoricView(users: users, userPasswords: $userPasswords)) {
                HStack {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Text("Count History")
                }
                .padding()
                .background(Color.blue.opacity(0.75))
                .foregroundColor(.primary)
                .cornerRadius(20)
                .padding(.horizontal, 16)
            }
            .padding(.top)

            // Ad/Map buttons
            if hasDemoDevice {
                Button(action: {
                    showDemoAdAlert = true
                }) {
                    HStack {
                        Image(systemName: "megaphone.fill")
                        Text("Create a Promo")
                    }
                    .padding()
                    .background(Color.orange.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
                .alert(isPresented: $showDemoAdAlert) {
                    Alert(
                        title: Text("Demo Mode"),
                        message: Text("You can't create a promotion with the demo.\n\nBut you can still give us money if you want... would be cool... please. Our venmo is @CrowdCount :)"),
                        dismissButton: .default(Text("Got it!"))
                    )
                }
            } else if isLocationOnMap {
                NavigationLink(destination: AdPayView(users: .constant(users), deviceLocationNames: deviceLocationNames, devicePrimaryDevices: devicePrimaryDevices)) {
                    HStack {
                        Image(systemName: "megaphone.fill")
                        Text("Create a Promo")
                    }
                    .padding()
                    .background(Color.orange.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            } else {
                NavigationLink(destination: GetOnMapInfoView()) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Get on the Map")
                    }
                    .padding()
                    .background(Color.green.opacity(0.75))
                    .foregroundColor(.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }

            Spacer()

            // Warning about extra devices not on map
            if !extraDevices.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(extraDevices.count) counter\(extraDevices.count == 1 ? " is" : "s are") not on the public map.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }

            // Warning about missing map devices
            if !missingMapDevices.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Add \(missingMapDevices.count) more counter\(missingMapDevices.count == 1 ? "" : "s") to complete this location: \(missingMapDevices.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
            }

            // Warning about offline counters
            if !offlineCounters.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.red)
                        .symbolRenderingMode(.hierarchical)
                    Text("\(offlineCounters.count) counter\(offlineCounters.count == 1 ? " is" : "s are") offline")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }

            Text("Counts and history are aggregated from all of your counters in \(locationName).")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
        .onAppear {
            checkIfLocationIsOnMap()
        }
    }

    /// Check if any device in this location is on the public map
    func checkIfLocationIsOnMap() {
        guard let url = URL(string: "\(serverURL)/get_all_location_data_with_extra") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Network error checking map locations: \(String(describing: error))")
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let locations = json["locations"] as? [[String: Any]] {

                var locationNames: [String: String] = [:]
                var primaryDevices: [String: String] = [:]

                for location in locations {
                    guard let primaryDeviceId = location["location_device"] as? String,
                          let mapLocationName = location["location_name"] as? String else {
                        continue
                    }

                    locationNames[primaryDeviceId] = mapLocationName
                    primaryDevices[primaryDeviceId] = primaryDeviceId

                    if let deviceBreakdown = location["device_breakdown"] as? [[String: Any]] {
                        for device in deviceBreakdown {
                            if let deviceId = device["device_id"] as? String {
                                locationNames[deviceId] = mapLocationName
                                primaryDevices[deviceId] = primaryDeviceId
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.deviceLocationNames = locationNames
                    self.devicePrimaryDevices = primaryDevices

                    // Check if ANY device in this location is on the map
                    let onMap = self.users.contains { locationNames.keys.contains($0.userId) }
                    self.isLocationOnMap = onMap

                    // Notify parent about map status change
                    self.onLocationMapStatusChanged(onMap)

                    // Pass map data to parent for device ownership checks
                    self.onMapDataFetched(locationNames, primaryDevices)
                }
            }
        }.resume()
    }
}

struct TotalCountView_Previews: PreviewProvider {
    static var previews: some View {
        TotalCountView(
            totalCount: 125,
            totalOvercrowdingCount: 200,
            users: [],
            userPasswords: .constant([:]),
            locationName: "Grand Central",
            alertViewModel: AlertViewModel(),
            serverURL: "https://api.example.com",
            onLocationMapStatusChanged: { _ in },
            onMapDataFetched: { _, _ in },
            isBluetoothSetupRequired: [:]
        )
    }
}
