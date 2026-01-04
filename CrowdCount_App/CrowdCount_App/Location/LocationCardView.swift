import SwiftUI

struct LocationCardView: View {
    let location: CrowdCountLocation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            // Header: Icon and connection status
            HStack {
                // Location icon
                ZStack {
                    Circle()
                        .fill(location.displayColor.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: location.displayIcon)
                        .font(.system(size: 18))
                        .foregroundColor(location.displayColor)
                }

                Spacer()

                // Connection status indicator
                connectionStatusView
            }

            // Location name
            HStack {
                Text(location.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Warning icon for negative counters
                if location.hasNegativeCounter && !location.isSingleCounter {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }

            // Count display
            HStack(alignment: .firstTextBaseline) {
                Text("\(location.currentCount)")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.primary)

                if let limit = location.overcrowdingLimit {
                    Text("/ \(limit)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Trend indicator
                if !location.comparisonSymbol.isEmpty {
                    Text(location.comparisonSymbol)
                        .font(.system(size: 20))
                        .foregroundColor(location.comparisonColor)
                        .padding(.leading, 4)
                }

                Spacer()
            }

            // Footer: Counter count
            HStack {
                Text(location.counterSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch location.connectionStatus {
        case .allOnline:
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Online")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        case .allOffline:
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("Offline")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        case .partial:
            HStack(spacing: 4) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Partial")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case .unknown:
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocationCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Single counter location
            LocationCardView(
                location: CrowdCountLocation(
                    id: "A1234",
                    name: "Main Entrance",
                    color: "blue",
                    icon: "door.left.hand.open",
                    comparison: "up",
                    counters: [
                        Counter(deviceId: "A1234", label: "Main Entrance", currentCount: 42, overcrowdingLimit: 100, connectionStatus: .online)
                    ],
                    isOnMap: true
                )
            )

            // Multi-counter location with negative
            LocationCardView(
                location: CrowdCountLocation(
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
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
