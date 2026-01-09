import SwiftUI

/// A view that shows the carousel of counters for a specific location
struct LocationCountersView: View {
    let locationId: UUID  // Use ID to look up current location from binding
    @Binding var users: [User]
    @Binding var totalCount: Int
    @Binding var userPasswords: [UUID: String]
    let setCurrentCount: (User, String) -> Void
    @Binding var isBluetoothSetupRequired: [UUID: Bool]
    @Binding var isCountLoaded: [UUID: Bool]  // Track if initial count has been fetched
    @ObservedObject var bluetoothManager: BluetoothManager
    let sendWiFiCredentials: () -> Void
    @Binding var deviceStatuses: [UUID: String]
    let serverURL: String
    let startDeviceStatusCheck: (User) -> Void
    @Binding var updateFrequencies: [UUID: Double]
    let logOut: (UUID) -> Void
    let startLiveCountUpdate: () -> Void

    // Location management
    @Binding var locations: [CounterLocation]
    let saveLocations: () -> Void
    let createLocation: (String) -> Void
    let deleteLocation: (UUID) -> Void
    @Binding var viewingLocationId: UUID?  // For switching locations
    @Binding var showLoginScreen: Bool  // For returning to login when last location deleted
    @ObservedObject var alertViewModel: AlertViewModel
    @Binding var newlyAddedDeviceId: String?  // For navigating to newly added device

    // For location picker sheet (local state, not shared)
    @State private var showLocationPicker: Bool = false
    @State private var showLocationSettings: Bool = false

    @State private var currentIndex: Int = 0

    // Map device data (fetched from TotalCountView)
    @State private var mapDeviceLocationNames: [String: String] = [:]
    @State private var mapDevicePrimaryDevices: [String: String] = [:]

    // Alert for when device is auto-moved to new location
    @State private var showDeviceMovedAlert: Bool = false
    @State private var movedDeviceLocationName: String = ""

    // Alert for creating new location for non-map counter
    @State private var showCreateLocationAlert: Bool = false
    @State private var pendingDeviceId: String = ""
    @State private var newLocationNameInput: String = ""

    /// Get current location from binding (always up to date)
    private var location: CounterLocation? {
        locations.first { $0.id == locationId }
    }

    /// Binding to the current location
    private var locationBinding: Binding<CounterLocation> {
        Binding(
            get: {
                location ?? CounterLocation(
                    id: locationId,
                    name: "Unknown",
                    deviceIds: [],
                    overcrowdingLimit: nil,
                    isMapLocation: false,
                    mapPrimaryDevice: nil
                )
            },
            set: { newValue in
                if let index = locations.firstIndex(where: { $0.id == locationId }) {
                    locations[index] = newValue
                }
            }
        )
    }

    /// Users that belong to this location
    private var locationUsers: [User] {
        guard let location = location else { return [] }
        return users.filter { location.deviceIds.contains($0.userId) }
    }

    /// Total count for this location
    private var locationTotalCount: Int {
        locationUsers.reduce(0) { $0 + $1.currentCount }
    }

    /// Overcrowding limit for this location
    private var locationOvercrowdingCount: Int {
        if let location = location, let limit = location.overcrowdingLimit {
            return limit
        }
        return locationUsers.compactMap { $0.overcrowdingLimit }.reduce(0, +)
    }

    /// Location name for display
    private var locationName: String {
        location?.name ?? "Location"
    }

    var body: some View {
        ZStack {
            // Background
            BlurredEdgesViewRepresentable(
                edgeColor: .label,
                edgeThickness: 10
            ).edgesIgnoringSafeArea(.all)

            VisualEffectView(
                effect: UIBlurEffect(style: .regular)
            ).edgesIgnoringSafeArea(.all)

            TabView(selection: $currentIndex) {
                // Total Count view (always show if location has counters)
                if !locationUsers.isEmpty {
                    TotalCountView(
                        totalCount: locationTotalCount,
                        totalOvercrowdingCount: locationOvercrowdingCount,
                        users: locationUsers,
                        userPasswords: $userPasswords,
                        locationName: locationName,
                        alertViewModel: alertViewModel,
                        serverURL: serverURL,
                        onLocationMapStatusChanged: { isOnMap in
                            // Update the location's isMapLocation status
                            if let index = locations.firstIndex(where: { $0.id == locationId }) {
                                if locations[index].isMapLocation != isOnMap {
                                    locations[index].isMapLocation = isOnMap
                                    saveLocations()
                                }
                            }
                        },
                        onMapDataFetched: { locationNames, primaryDevices in
                            // Store map data for device ownership checks
                            mapDeviceLocationNames = locationNames
                            mapDevicePrimaryDevices = primaryDevices

                            // Update location name from map if any device is on the map
                            if let index = locations.firstIndex(where: { $0.id == locationId }) {
                                // Find first device in this location that's on the map
                                for user in locationUsers {
                                    if let mapLocationName = locationNames[user.userId] {
                                        // Update location name to match map
                                        if locations[index].name != mapLocationName {
                                            locations[index].name = mapLocationName
                                            locations[index].isMapLocation = true
                                            locations[index].mapPrimaryDevice = primaryDevices[user.userId]
                                            saveLocations()
                                            print("[LocationCountersView.onMapDataFetched] Updated location name to '\(mapLocationName)' from map")
                                        }
                                        break  // Use first map device found
                                    }
                                }
                            }
                        },
                        isBluetoothSetupRequired: isBluetoothSetupRequired,
                        isCountLoaded: isCountLoaded,
                        location: locationBinding,
                        onLocationUpdated: { updatedLocation in
                            // Save the updated location
                            if let index = locations.firstIndex(where: { $0.id == locationId }) {
                                locations[index] = updatedLocation
                                saveLocations()
                            }
                        }
                    )
                    .tag(0)
                }

                // All counters stacked on one page
                if !locationUsers.isEmpty {
                    CountersListView(
                        users: locationUsers,
                        allUsers: $users,
                        userPasswords: $userPasswords,
                        serverURL: serverURL,
                        setCurrentCount: setCurrentCount,
                        isBluetoothSetupRequired: isBluetoothSetupRequired,
                        isCountLoaded: isCountLoaded,
                        bluetoothManager: bluetoothManager,
                        sendWiFiCredentials: sendWiFiCredentials,
                        isLocationOnMap: location?.isMapLocation ?? false,
                        mapDeviceIds: Set(mapDeviceLocationNames.keys),
                        updateFrequencies: $updateFrequencies,
                        logOut: logOut
                    )
                    .tag(1)
                }

                // Add Device page (rightmost)
                AddUserPage(
                    users: $users,
                    totalCount: $totalCount,
                    userPasswords: $userPasswords,
                    serverURL: serverURL,
                    startDeviceStatusCheck: startDeviceStatusCheck,
                    startLiveCountUpdate: startLiveCountUpdate,
                    onDeviceAdded: { deviceId in
                        let currentLocationIsOnMap = location?.isMapLocation ?? false

                        if let deviceMapLocationName = mapDeviceLocationNames[deviceId] {
                            // Device is on the map
                            if deviceMapLocationName == locationName {
                                // Device belongs to THIS map location - add normally
                                if let index = locations.firstIndex(where: { $0.id == locationId }) {
                                    if !locations[index].deviceIds.contains(deviceId) {
                                        locations[index].deviceIds.append(deviceId)
                                        saveLocations()
                                        // Navigate to the newly added device
                                        newlyAddedDeviceId = deviceId
                                        print("[LocationCountersView.onDeviceAdded] Added map device '\(deviceId)' to its map location")
                                    }
                                }
                            } else {
                                // Device belongs to a DIFFERENT map location - create new location for it
                                let newLocationId = UUID()
                                let newLocation = CounterLocation(
                                    id: newLocationId,
                                    name: deviceMapLocationName,
                                    deviceIds: [deviceId],
                                    overcrowdingLimit: nil,
                                    isMapLocation: true,
                                    mapPrimaryDevice: mapDevicePrimaryDevices[deviceId]
                                )
                                locations.append(newLocation)
                                saveLocations()

                                // Show alert explaining what happened
                                movedDeviceLocationName = deviceMapLocationName
                                showDeviceMovedAlert = true

                                // Navigate to the new location and the device
                                viewingLocationId = newLocationId
                                newlyAddedDeviceId = deviceId

                                print("[LocationCountersView.onDeviceAdded] Device belongs to different map location '\(deviceMapLocationName)' - created new location and navigating to it")
                            }
                        } else if currentLocationIsOnMap {
                            // Device is NOT on the map, but current location IS a map location
                            // Prompt user to create a new location for this counter
                            pendingDeviceId = deviceId
                            newLocationNameInput = ""
                            showCreateLocationAlert = true
                            print("[LocationCountersView.onDeviceAdded] Non-map device '\(deviceId)' cannot be added to map location - prompting for new location")
                        } else {
                            // Device is NOT on the map and current location is NOT a map location - add normally
                            if let index = locations.firstIndex(where: { $0.id == locationId }) {
                                if !locations[index].deviceIds.contains(deviceId) {
                                    locations[index].deviceIds.append(deviceId)
                                    saveLocations()
                                    // Navigate to the newly added device
                                    newlyAddedDeviceId = deviceId
                                    print("[LocationCountersView.onDeviceAdded] Added non-map device '\(deviceId)' to local location")
                                }
                            }
                        }
                    },
                    isInLocationView: true,
                    isLocationOnMap: location?.isMapLocation ?? false,
                    locationHasCounters: !locationUsers.isEmpty,
                    locationName: locationName,
                    onDeleteLocation: {
                        // Delete this location and navigate away
                        deleteLocation(locationId)
                        viewingLocationId = nil
                        // If this was the last location, go to login screen
                        if locations.isEmpty {
                            showLoginScreen = true
                        }
                    },
                    alertViewModel: alertViewModel
                )
                .tag(locationUsers.isEmpty ? 0 : 2)  // If empty, AddUser is at 0; otherwise at index 2 (after TotalCount and CountersList)
            }
            .tabViewStyle(PageTabViewStyle())
            .id(locationId)  // Force new view when switching locations (resets state including currentIndex)
            .onAppear {
                setupPageControlAppearance()
                // Note: currentIndex defaults to 0 and is reset when locationId changes due to .id() modifier
                // Always fetch map data so we have it available for device addition
                fetchMapData()
            }
            .onChange(of: locationUsers.count) { oldCount, newCount in
                // Reset tab index if it's out of bounds
                // If empty: just AddUser (0)
                // If has users: TotalCount (0), CountersList (1), AddUser (2)
                let maxIndex = newCount == 0 ? 1 : 3
                if currentIndex >= maxIndex {
                    currentIndex = max(0, maxIndex - 1)
                }
            }
            .onChange(of: newlyAddedDeviceId) { _, deviceId in
                // Navigate to the counters list when a device is added
                if deviceId != nil {
                    withAnimation {
                        currentIndex = 1  // CountersList page
                    }
                    // Clear the newlyAddedDeviceId after navigating
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        newlyAddedDeviceId = nil
                    }
                }
            }

            // Floating buttons (bottom)
            VStack {
                Spacer()
                HStack {
                    // Map button (left)
                    NavigationLink(destination: MapContentView()) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "map.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                                .glassEffect(.regular.interactive())
                        } else {
                            Image(systemName: "map.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    .padding(.leading, 20)

                    Spacer()

                    // Location button (right) - same style as map button
                    Button(action: { showLocationPicker = true }) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                                .glassEffect(.regular.interactive())
                        } else {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.75))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(locationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 14) {
                    NavigationLink(destination: InformationView()) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "info")
                                .foregroundColor(.primary)
                        } else {
                            Image(systemName: "info.circle")
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.leading, alertViewModel.alertExists ? 8 : 0)
                    if alertViewModel.alertExists {
                        Button(action: {
                            alertViewModel.showAlert = true
                        }) {
                            if #available(iOS 26.0, *) {
                                Image(systemName: "bell.badge.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.red, .primary)
                            } else {
                                Image(systemName: "bell.badge.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showLocationSettings = true
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.primary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                locations: $locations,
                users: users,
                currentlyViewingLocationId: locationId,  // We're in this location
                onSave: saveLocations,
                onCreate: createLocation,
                onDelete: deleteLocation,
                onNavigateToLocation: { location in
                    // Switch to another location
                    viewingLocationId = location.id
                },
                onGoToAllCounters: {
                    // Switch to all counters view
                    viewingLocationId = nil
                },
                mapDeviceIds: Set(mapDeviceLocationNames.keys),
                isBluetoothSetupRequired: isBluetoothSetupRequired,
                userPasswords: userPasswords,
                serverURL: serverURL
            )
        }
        .sheet(isPresented: $showLocationSettings) {
            LocationSettingsView(
                location: locationBinding,
                users: users,
                onSave: saveLocations,
                onDelete: {
                    deleteLocation(locationId)
                    viewingLocationId = nil
                    if locations.isEmpty {
                        showLoginScreen = true
                    }
                },
                mapDeviceIds: Set(mapDeviceLocationNames.keys),
                isBluetoothSetupRequired: isBluetoothSetupRequired,
                userPasswords: userPasswords,
                serverURL: serverURL
            )
        }
        .alert("Counter Added to Different Location", isPresented: $showDeviceMovedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This counter belongs to '\(movedDeviceLocationName)' on the public map. A new location has been created for it.")
        }
        .alert("Create New Location", isPresented: $showCreateLocationAlert) {
            TextField("Location name", text: $newLocationNameInput)
            Button("Cancel", role: .cancel) {
                pendingDeviceId = ""
                newLocationNameInput = ""
            }
            Button("Create") {
                if !newLocationNameInput.isEmpty && !pendingDeviceId.isEmpty {
                    let deviceId = pendingDeviceId
                    let newLocationId = UUID()
                    let newLocation = CounterLocation(
                        id: newLocationId,
                        name: newLocationNameInput,
                        deviceIds: [deviceId],
                        overcrowdingLimit: nil,
                        isMapLocation: false,
                        mapPrimaryDevice: nil
                    )
                    locations.append(newLocation)
                    saveLocations()

                    // Navigate to the new location and the device
                    viewingLocationId = newLocationId
                    newlyAddedDeviceId = deviceId

                    print("[LocationCountersView] Created new location '\(newLocationNameInput)' for non-map device '\(deviceId)' - navigating to it")
                }
                pendingDeviceId = ""
                newLocationNameInput = ""
            }
        } message: {
            Text("This counter is not part of '\(locationName)' on the public map. Please create a new location for it.")
        }
    }

    private func setupPageControlAppearance() {
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.label
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
    }

    /// Fetch map data to determine which devices belong to which map locations
    private func fetchMapData() {
        guard let url = URL(string: "\(serverURL)/locations") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let locationsArray = json["locations"] as? [[String: Any]] {

                    var locationNames: [String: String] = [:]
                    var primaryDevices: [String: String] = [:]

                    for locationJson in locationsArray {
                        guard let name = locationJson["name"] as? String,
                              let devices = locationJson["devices"] as? [[String: Any]] else { continue }

                        let primaryDevice = locationJson["primary_device"] as? String

                        for device in devices {
                            if let deviceId = device["device_id"] as? String {
                                locationNames[deviceId] = name
                                if let primary = primaryDevice {
                                    primaryDevices[deviceId] = primary
                                }
                            }
                        }
                    }

                    DispatchQueue.main.async {
                        self.mapDeviceLocationNames = locationNames
                        self.mapDevicePrimaryDevices = primaryDevices
                        print("[LocationCountersView.fetchMapData] Fetched map data: \(locationNames.count) devices")
                    }
                }
            } catch {
                print("[LocationCountersView.fetchMapData] Error parsing map data: \(error)")
            }
        }.resume()
    }
}
