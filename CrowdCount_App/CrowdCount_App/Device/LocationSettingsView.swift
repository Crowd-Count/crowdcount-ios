import SwiftUI

struct LocationSettingsView: View {
    @Binding var location: CounterLocation
    let users: [User]  // All users (to show which are in this location)
    let onSave: () -> Void
    let onDelete: () -> Void
    let mapDeviceIds: Set<String>  // Device IDs that are on the public map
    let isBluetoothSetupRequired: [UUID: Bool]  // Offline status for each device

    @Environment(\.dismiss) var dismiss
    @State private var locationName: String = ""
    @State private var selectedColor: String = "orange"
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // Location Name
                Section(header: Text("Location Name"), footer: location.isMapLocation ? Text("Name is synced from the public map. Email info@crowdcount.tech to request changes.") : nil) {
                    if location.isMapLocation {
                        Text(locationName)
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Location name", text: $locationName)
                            .onChange(of: locationName) { _, newValue in
                                location.name = newValue
                            }
                    }
                }

                // Folder Color
                Section(header: Text("Folder Color")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(CounterLocation.availableColors, id: \.name) { colorOption in
                            Button(action: {
                                selectedColor = colorOption.name
                                location.colorName = colorOption.name
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 36, height: 36)
                                    if selectedColor == colorOption.name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Counters in this location
                Section(header: Text("Counters (\(location.deviceIds.count))")) {
                    if location.deviceIds.isEmpty {
                        Text("No counters in this location")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(location.deviceIds, id: \.self) { deviceId in
                            HStack {
                                if isDeviceOffline(deviceId: deviceId) {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.red)
                                        .symbolRenderingMode(.hierarchical)
                                } else {
                                    Image(systemName: "wifi")
                                        .foregroundColor(.green)
                                }
                                VStack(alignment: .leading) {
                                    Text(deviceNickname(for: deviceId))
                                        .font(.body)
                                    Text(deviceId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                // Show warning if this counter is not on the map (only for map locations)
                                if location.isMapLocation && !mapDeviceIds.contains(deviceId) && deviceId != "Demo" {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // Warning about non-map counters (only for map locations)
                if location.isMapLocation {
                    let nonMapCounters = location.deviceIds.filter { !mapDeviceIds.contains($0) && $0 != "Demo" }
                    if !nonMapCounters.isEmpty {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(nonMapCounters.count) counter\(nonMapCounters.count == 1 ? " is" : "s are") not on the public map.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                // Location Info
                Section(header: Text("Info"), footer: infoFooter) {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(location.isMapLocation ? "Live on Map" : "Local")
                            .foregroundColor(location.isMapLocation ? .green : .secondary)
                    }
                }

                // Delete Location
                Section {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Delete Location")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Location Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationName = location.name
                selectedColor = location.colorName ?? "orange"
            }
            .alert("Delete Location?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will remove the location and all counters in it. You will need to re-add the counters if you want to use them again.")
            }
        }
    }

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local: This location is only stored on this device.")
            Text("Live on Map: This location is visible on the public map with live count updates.")
        }
    }

    private func deviceNickname(for deviceId: String) -> String {
        // Try to get custom nickname from UserDefaults
        if let name = UserDefaults.standard.string(forKey: deviceId), !name.isEmpty {
            return name
        }
        // No nickname set - show "Counter {deviceId}"
        return "Counter \(deviceId)"
    }

    private func isDeviceOffline(deviceId: String) -> Bool {
        // Find the user with this deviceId and check their offline status
        if let user = users.first(where: { $0.userId == deviceId }) {
            return isBluetoothSetupRequired[user.id] == true
        }
        return false
    }
}

#Preview {
    LocationSettingsView(
        location: .constant(CounterLocation(
            id: UUID(),
            name: "Grand Central",
            deviceIds: ["T0001", "T0002"],
            overcrowdingLimit: 2000,
            isMapLocation: true,
            mapPrimaryDevice: "T0001"
        )),
        users: [],
        onSave: {},
        onDelete: {},
        mapDeviceIds: ["T0001"],  // T0002 will show warning
        isBluetoothSetupRequired: [:]
    )
}
