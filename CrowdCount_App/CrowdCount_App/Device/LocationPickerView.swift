import SwiftUI

struct LocationPickerView: View {
    @Binding var locations: [AppLocation]
    let devices: [Device]
    let deviceStatuses: [String: String]
    let currentlyViewingLocationId: String?
    let onSave: () -> Void
    let onDelete: (String) -> Void
    let onNavigateToLocation: (AppLocation) -> Void
    let onGoToAllLocations: () -> Void
    let onCreate: (String) async -> AppLocation?
    @ObservedObject var alertViewModel: AlertViewModel

    @Environment(\.dismiss) var dismiss
    @State private var editingLocationId: String? = nil
    @State private var editingName: String = ""
    @State private var settingsLocationIndex: Int? = nil
    @State private var showCreateLocation: Bool = false
    @State private var newLocationName: String = ""
    @State private var isCreating: Bool = false

    private var isInLocationView: Bool {
        currentlyViewingLocationId != nil
    }

    var body: some View {
        NavigationView {
            listContent
                .navigationTitle("Locations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert("Rename Location", isPresented: renameBinding) {
                    renameAlertContent
                } message: {
                    Text("Enter a new name for this location")
                }
                .sheet(isPresented: settingsBinding) {
                    settingsSheetContent
                }
                .alert("Create Location", isPresented: $showCreateLocation) {
                    createAlertContent
                } message: {
                    Text("Enter a name for the new location")
                }
        }
    }

    // MARK: - Subviews

    private var listContent: some View {
        List {
            // "All Locations" option
            Section {
                Button(action: {
                    onGoToAllLocations()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.blue)
                        Text("All Locations")
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
                        locationRow(index: index, location: location)
                    }
                }
            }

            // Create Location
            Section {
                Button(action: {
                    newLocationName = ""
                    showCreateLocation = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("Create Location")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(devices.isEmpty)
            }
        }
    }

    private func locationRow(index: Int, location: AppLocation) -> some View {
        HStack {
            Image(systemName: "folder.fill")
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

    // MARK: - Alert / Sheet Bindings

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { editingLocationId != nil },
            set: { if !$0 { editingLocationId = nil } }
        )
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { settingsLocationIndex != nil },
            set: { if !$0 { settingsLocationIndex = nil } }
        )
    }

    // MARK: - Alert / Sheet Content

    @ViewBuilder
    private var renameAlertContent: some View {
        TextField("Location name", text: $editingName)
        Button("Cancel", role: .cancel) {
            editingLocationId = nil
            editingName = ""
        }
        Button("Save") {
            if let id = editingLocationId,
               let index = locations.firstIndex(where: { $0.id == id }) {
                let oldName = locations[index].name
                locations[index].name = editingName

                // Update name on server
                let location = locations[index]
                let creds = devices.filter { location.deviceIds.contains($0.deviceId) }
                    .map { ["device_id": $0.deviceId, "password": $0.password] }
                if let firstDevice = devices.first(where: { location.deviceIds.contains($0.deviceId) }) {
                    Task {
                        do {
                            try await APIService.shared.updateLocation(
                                locationId: location.id,
                                name: editingName,
                                overcrowdingLimit: nil,
                                credentials: creds,
                                signingDevice: (firstDevice.deviceId, firstDevice.password)
                            )
                        } catch {
                            print("Error renaming location on server: \(error)")
                            await MainActor.run {
                                if let idx = locations.firstIndex(where: { $0.id == id }) {
                                    locations[idx].name = oldName
                                }
                            }
                        }
                    }
                }
                onSave()
            }
            editingLocationId = nil
            editingName = ""
        }
    }

    @ViewBuilder
    private var settingsSheetContent: some View {
        if let index = settingsLocationIndex, index < locations.count {
            LocationSettingsView(
                location: $locations[index],
                devices: devicesForLocation(locations[index]),
                deviceStatuses: deviceStatuses,
                onSave: { updatedLocation in
                    if let idx = locations.firstIndex(where: { $0.id == updatedLocation.id }) {
                        locations[idx] = updatedLocation
                    }
                    onSave()
                },
                onDelete: {
                    onDelete(locations[index].id)
                    settingsLocationIndex = nil
                }
            )
        }
    }

    @ViewBuilder
    private var createAlertContent: some View {
        TextField("Location name", text: $newLocationName)
        Button("Cancel", role: .cancel) {
            newLocationName = ""
        }
        Button("Create") {
            let name = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            isCreating = true
            Task {
                if let newLocation = await onCreate(name) {
                    await MainActor.run {
                        onNavigateToLocation(newLocation)
                        isCreating = false
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        isCreating = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func offlineCount(for location: AppLocation) -> Int {
        location.deviceIds.filter { deviceStatuses[$0] != "online" }.count
    }

    private func devicesForLocation(_ location: AppLocation) -> [Device] {
        devices.filter { location.deviceIds.contains($0.deviceId) }
    }
}
