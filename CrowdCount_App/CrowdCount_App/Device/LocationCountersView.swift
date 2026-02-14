import SwiftUI

struct LocationCountersView: View {
    let location: AppLocation
    let currentCount: Int
    let devices: [Device]
    @Binding var deviceStatuses: [String: String]
    @Binding var locations: [AppLocation]
    @Binding var viewingLocationId: String?
    @Binding var showLoginScreen: Bool
    @ObservedObject var alertViewModel: AlertViewModel
    let incompleteLocationWarnings: [IncompleteLocationWarning]
    let onDismissIncompleteWarning: (String, Int) -> Void  // (warningId, deviceCount)
    let addToCount: (Int) -> Void
    let subFromCount: (Int) -> Void
    let addDeviceToLocation: (String, String, String) async -> Void // (deviceId, password, label)
    let removeDeviceFromLocation: (String) async -> Void
    let deleteLocation: (String) -> Void
    let logOut: (String) -> Void
    let saveLocations: () -> Void
    let createLocation: (String) async -> AppLocation?

    @State private var showLocationPicker: Bool = false
    @State private var showLocationSettings: Bool = false
    @State private var currentIndex: Int = 0

    /// Live location from the binding (always up-to-date after settings changes)
    private var liveLocation: AppLocation {
        locations.first(where: { $0.id == location.id }) ?? location
    }

    /// Devices that belong to this location
    private var locationDevices: [Device] {
        devices.filter { liveLocation.deviceIds.contains($0.deviceId) }
    }

    var body: some View {
        ZStack {
            BlurredEdgesViewRepresentable(
                edgeColor: .label,
                edgeThickness: 10
            ).edgesIgnoringSafeArea(.all)

            VisualEffectView(
                effect: UIBlurEffect(style: .regular)
            ).edgesIgnoringSafeArea(.all)

            TabView(selection: $currentIndex) {
                // Page 0: Location total count with +/- buttons
                if !locationDevices.isEmpty {
                    LocationTotalCountView(
                        currentCount: currentCount,
                        overcrowdingLimit: liveLocation.overcrowdingLimit,
                        locationName: liveLocation.name,
                        locationId: liveLocation.id,
                        devices: locationDevices,
                        deviceStatuses: deviceStatuses,
                        alertViewModel: alertViewModel,
                        incompleteLocationWarnings: incompleteLocationWarnings,
                        onDismissIncompleteWarning: onDismissIncompleteWarning,
                        addToCount: addToCount,
                        subFromCount: subFromCount,
                        location: locationBinding,
                        onLocationUpdated: { updatedLocation in
                            if let index = locations.firstIndex(where: { $0.id == location.id }) {
                                locations[index] = updatedLocation
                                saveLocations()
                            }
                        }
                    )
                    .tag(0)
                }

                // Page 1: Device management list
                if !locationDevices.isEmpty {
                    DeviceManagementListView(
                        location: liveLocation,
                        devices: locationDevices,
                        deviceStatuses: deviceStatuses,
                        removeDeviceFromLocation: removeDeviceFromLocation,
                        logOut: logOut
                    )
                    .tag(1)
                }

                // Page 2: Add device to location
                AddDeviceToLocationView(
                    locationName: liveLocation.name,
                    addDeviceToLocation: addDeviceToLocation,
                    alertViewModel: alertViewModel,
                    locationHasDevices: !locationDevices.isEmpty,
                    isOnMap: liveLocation.isOnMap,
                    onDeleteLocation: {
                        deleteLocation(location.id)
                    },
                    onOpenLocationList: {
                        showLocationPicker = true
                    }
                )
                .tag(locationDevices.isEmpty ? 0 : 2)
            }
            .tabViewStyle(PageTabViewStyle())
            .id(location.id)
            .onAppear {
                setupPageControlAppearance()
            }
            .onChange(of: currentIndex) { _, _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onChange(of: locationDevices.count) { oldCount, newCount in
                if newCount > oldCount {
                    currentIndex = 1
                }
            }

            // Floating buttons (bottom)
            VStack {
                Spacer()
                HStack {
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
        .navigationTitle(liveLocation.name)
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
                devices: devices,
                deviceStatuses: deviceStatuses,
                currentlyViewingLocationId: liveLocation.id,
                onSave: saveLocations,
                onDelete: { locationId in
                    deleteLocation(locationId)
                },
                onNavigateToLocation: { loc in
                    viewingLocationId = loc.id
                },
                onGoToAllLocations: {
                    viewingLocationId = nil
                },
                onCreate: { name in
                    await createLocation(name)
                },
                alertViewModel: alertViewModel
            )
        }
        .sheet(isPresented: $showLocationSettings) {
            LocationSettingsView(
                location: locationBinding,
                devices: devices.filter { liveLocation.deviceIds.contains($0.deviceId) },
                deviceStatuses: deviceStatuses,
                onSave: { updatedLocation in
                    if let index = locations.firstIndex(where: { $0.id == location.id }) {
                        locations[index] = updatedLocation
                    }
                    saveLocations()
                },
                onDelete: {
                    deleteLocation(location.id)
                },
                removeDeviceFromLocation: removeDeviceFromLocation
            )
        }
    }

    /// Binding to the current location in the locations array
    private var locationBinding: Binding<AppLocation> {
        Binding(
            get: {
                locations.first { $0.id == location.id } ?? location
            },
            set: { newValue in
                if let index = locations.firstIndex(where: { $0.id == location.id }) {
                    locations[index] = newValue
                }
            }
        )
    }

    private func setupPageControlAppearance() {
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.label
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
    }
}
