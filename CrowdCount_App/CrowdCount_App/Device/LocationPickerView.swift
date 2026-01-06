import SwiftUI

struct LocationPickerView: View {
    @Binding var locations: [CounterLocation]
    let users: [User]  // Pass users for LocationSettingsView
    let currentlyViewingLocationId: UUID?  // Which location is currently being viewed (nil = main/all)
    let onSave: () -> Void
    let onCreate: (String) -> Void
    let onDelete: (UUID) -> Void
    let onNavigateToLocation: (CounterLocation) -> Void  // Navigate to location page
    let onGoToAllCounters: () -> Void  // Go back to main view (pops navigation)
    let mapDeviceIds: Set<String>  // Device IDs that are on the public map
    let isBluetoothSetupRequired: [UUID: Bool]  // Offline status for each device

    @Environment(\.dismiss) var dismiss
    @State private var showAddLocation: Bool = false
    @State private var newLocationName: String = ""
    @State private var editingLocationId: UUID? = nil
    @State private var editingName: String = ""
    @State private var settingsLocationIndex: Int? = nil

    /// Whether we're currently viewing from inside a location
    private var isInLocationView: Bool {
        currentlyViewingLocationId != nil
    }

    var body: some View {
        NavigationView {
            List {
                // "All Counters" option
                Section {
                    Button(action: {
                        onGoToAllCounters()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.blue)
                            Text("All Counters")
                                .foregroundColor(.primary)
                            Spacer()
                            if !isInLocationView {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Location list
                if !locations.isEmpty {
                    Section(header: Text("Locations")) {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                            HStack {
                                Image(systemName: location.isMapLocation ? "mappin.circle.fill" : "folder.fill")
                                    .foregroundColor(location.folderColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .foregroundColor(.primary)
                                    HStack(spacing: 4) {
                                        Text("\(location.deviceIds.count) counter\(location.deviceIds.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if offlineCount(for: location) > 0 {
                                            Text("- \(offlineCount(for: location)) offline")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                                Spacer()
                                if currentlyViewingLocationId == location.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }

                                // Settings button
                                Button(action: {
                                    settingsLocationIndex = index
                                }) {
                                    Image(systemName: "gearshape.fill")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 8)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // If already viewing this location, just dismiss
                                if currentlyViewingLocationId == location.id {
                                    dismiss()
                                } else {
                                    onNavigateToLocation(location)
                                    dismiss()
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDelete(location.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingLocationId = location.id
                                    editingName = location.name
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                // Add location
                Section {
                    Button(action: {
                        showAddLocation = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Location")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("New Location", isPresented: $showAddLocation) {
                TextField("Location name", text: $newLocationName)
                Button("Cancel", role: .cancel) {
                    newLocationName = ""
                }
                Button("Create") {
                    if !newLocationName.isEmpty {
                        onCreate(newLocationName)
                        newLocationName = ""
                    }
                }
            } message: {
                Text("Enter a name for the new location")
            }
            .alert("Rename Location", isPresented: Binding(
                get: { editingLocationId != nil },
                set: { if !$0 { editingLocationId = nil } }
            )) {
                TextField("Location name", text: $editingName)
                Button("Cancel", role: .cancel) {
                    editingLocationId = nil
                    editingName = ""
                }
                Button("Save") {
                    if let id = editingLocationId,
                       let index = locations.firstIndex(where: { $0.id == id }) {
                        locations[index].name = editingName
                        onSave()
                    }
                    editingLocationId = nil
                    editingName = ""
                }
            } message: {
                Text("Enter a new name for this location")
            }
            .sheet(isPresented: Binding(
                get: { settingsLocationIndex != nil },
                set: { if !$0 { settingsLocationIndex = nil } }
            )) {
                if let index = settingsLocationIndex, index < locations.count {
                    LocationSettingsView(
                        location: $locations[index],
                        users: users,
                        onSave: onSave,
                        onDelete: {
                            onDelete(locations[index].id)
                            settingsLocationIndex = nil
                        },
                        mapDeviceIds: mapDeviceIds,
                        isBluetoothSetupRequired: isBluetoothSetupRequired
                    )
                }
            }
        }
    }

    /// Count how many devices in a location are offline
    private func offlineCount(for location: CounterLocation) -> Int {
        var count = 0
        for deviceId in location.deviceIds {
            if let user = users.first(where: { $0.userId == deviceId }),
               isBluetoothSetupRequired[user.id] == true {
                count += 1
            }
        }
        return count
    }
}

#Preview {
    LocationPickerView(
        locations: .constant([
            CounterLocation(id: UUID(), name: "Grand Central", deviceIds: ["T0001", "T0002"], overcrowdingLimit: 2000, isMapLocation: true, mapPrimaryDevice: "T0001"),
            CounterLocation(id: UUID(), name: "My Local", deviceIds: ["T0003"], overcrowdingLimit: nil, isMapLocation: false, mapPrimaryDevice: nil)
        ]),
        users: [],
        currentlyViewingLocationId: nil,
        onSave: {},
        onCreate: { _ in },
        onDelete: { _ in },
        onNavigateToLocation: { _ in },
        onGoToAllCounters: {},
        mapDeviceIds: ["T0001"],
        isBluetoothSetupRequired: [:]
    )
}
