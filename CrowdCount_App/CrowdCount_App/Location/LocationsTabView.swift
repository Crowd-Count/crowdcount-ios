import SwiftUI

struct LocationsTabView: View {
    @Binding var locations: [CrowdCountLocation]
    @Binding var counterPasswords: [String: String] // deviceId -> password
    let serverURL: String
    let onAddDevice: () -> Void
    let onModifyCount: (Counter) -> Void
    let onViewHistory: (Counter) -> Void
    let onViewAggregatedHistory: (CrowdCountLocation) -> Void

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Location cards with navigation
                LazyVStack(spacing: 16) {
                    ForEach(locations) { location in
                        NavigationLink(value: location) {
                            LocationCardView(location: location)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)

                // Add device button
                addDeviceButton
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(for: CrowdCountLocation.self) { location in
            LocationDetailView(
                location: location,
                counterPasswords: counterPasswords,
                onModifyCount: onModifyCount,
                onViewHistory: onViewHistory,
                onViewAggregatedHistory: { onViewAggregatedHistory(location) }
            )
        }
    }

    // MARK: - Add Device Button

    private var addDeviceButton: some View {
        Button(action: onAddDevice) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Add Counter")
                    .font(.headline)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
        }
    }
}

// MARK: - Empty State View

struct NoLocationsView: View {
    let onAddDevice: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Locations Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add a counter device to get started.\nCounters will be grouped by location.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAddDevice) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Counter")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
struct LocationsTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LocationsTabView(
                locations: .constant([
                    CrowdCountLocation(
                        id: "A1234",
                        name: "Main Entrance",
                        color: "blue",
                        icon: "door.left.hand.open",
                        comparison: "up",
                        counters: [
                            Counter(deviceId: "A1234", label: "Main Entrance", currentCount: 42, overcrowdingLimit: 100, connectionStatus: .online)
                        ],
                        isOnMap: true
                    ),
                    CrowdCountLocation(
                        id: "B5678",
                        name: "Library",
                        color: "green",
                        icon: "books.vertical",
                        comparison: "down",
                        counters: [
                            Counter(deviceId: "B5678", label: "North Door", currentCount: 25, overcrowdingLimit: 50, connectionStatus: .online),
                            Counter(deviceId: "C9012", label: "South Door", currentCount: -3, overcrowdingLimit: 30, connectionStatus: .online),
                            Counter(deviceId: "D3456", label: "Emergency Exit", currentCount: 5, connectionStatus: .offline)
                        ],
                        isOnMap: true
                    )
                ]),
                counterPasswords: .constant(["A1234": "pass1", "B5678": "pass2", "C9012": "pass3", "D3456": "pass4"]),
                serverURL: "https://api.crowdcount.tech",
                onAddDevice: {},
                onModifyCount: { _ in },
                onViewHistory: { _ in },
                onViewAggregatedHistory: { _ in }
            )
        }
        .environmentObject(AppSettings())
    }
}
#endif
