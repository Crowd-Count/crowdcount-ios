import SwiftUI

/// Shows all locations as cards when no specific location is selected
struct AllLocationsListView: View {
    let locations: [AppLocation]
    let locationCounts: [String: Int]
    let locationClosedStates: [String: Bool]
    let deviceCounts: [String: Int]
    let devices: [Device]
    let deviceStatuses: [String: String]
    let onSelectLocation: (AppLocation) -> Void
    let onOpenLocationPicker: () -> Void
    let alertViewModel: AlertViewModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text("Locations")
                            .font(.title2.bold())
                        Spacer()
                    }
                    .padding(.top, 8)

                    if locations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.secondary)
                            Text("No locations yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(locations) { location in
                            LocationCardView(
                                location: location,
                                count: locationCounts[location.id] ?? 0,
                                isClosed: locationClosedStates[location.id] ?? false,
                                deviceCount: location.deviceIds.count,
                                offlineCount: offlineCount(for: location),
                                onTap: { onSelectLocation(location) },
                                deviceRows: deviceRows(for: location)
                            )
                        }
                    }

                    // Footer
                    VStack(spacing: 8) {
                        Divider()
                            .padding(.top, 8)

                        Text("Tap a location to view its live count.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: onOpenLocationPicker) {
                            Text("Manage Locations")
                                .font(.footnote.bold())
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func offlineCount(for location: AppLocation) -> Int {
        location.deviceIds.filter { deviceStatuses[$0] != "online" }.count
    }

    private func deviceRows(for location: AppLocation) -> [(name: String, deviceId: String, count: Int, isOffline: Bool)] {
        location.deviceIds.compactMap { deviceId in
            guard devices.contains(where: { $0.deviceId == deviceId }) else { return nil }
            let name = NicknameManager.shared.displayName(for: deviceId)
            let count = deviceCounts[deviceId] ?? 0
            let isOffline = deviceStatuses[deviceId] != "online"
            return (name: name, deviceId: deviceId, count: count, isOffline: isOffline)
        }
    }
}

/// A card representing a single location with optional per-device rows
struct LocationCardView: View {
    let location: AppLocation
    let count: Int
    let isClosed: Bool
    let deviceCount: Int
    let offlineCount: Int
    let onTap: () -> Void
    let deviceRows: [(name: String, deviceId: String, count: Int, isOffline: Bool)]

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Location header row
                HStack(spacing: 12) {
                    if location.isOnMap, let icon = location.mapIcon, let color = location.mapColor {
                        ZStack {
                            Circle()
                                .fill(Color.fromString(color).opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(Color.fromString(color))
                        }
                    } else {
                        Image(systemName: "folder.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(location.folderColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text("\(deviceCount) counter\(deviceCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if offlineCount > 0 {
                                Text("- \(offlineCount) offline")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Spacer()

                    // Total count
                    if isClosed {
                        Text("Closed")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    } else if let limit = location.overcrowdingLimit, limit > 0 {
                        HStack(spacing: 0) {
                            Text("\(count)")
                                .font(.title2.bold())
                                .monospacedDigit()
                                .foregroundColor(count >= limit ? .red : .primary)
                            Text(" / \(limit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("\(count)")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Per-device rows (only show if more than 1 device)
                if deviceRows.count > 1 {
                    Divider()
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(deviceRows, id: \.deviceId) { row in
                            HStack(spacing: 8) {
                                Image(systemName: row.isOffline ? "wifi.slash" : "wifi")
                                    .foregroundColor(row.isOffline ? .red : .green)
                                    .font(.system(size: 12))
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 16)

                                Text(row.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                if row.name != row.deviceId {
                                    Text(row.deviceId)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}
