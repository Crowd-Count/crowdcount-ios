import SwiftUI

struct LocationDetailView: View {
    let location: CrowdCountLocation
    let counterPasswords: [String: String] // deviceId -> password
    let onModifyCount: (Counter) -> Void
    let onViewHistory: (Counter) -> Void
    let onViewAggregatedHistory: () -> Void

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header card with aggregated info
                headerCard

                // Negative count warning (if applicable and not seen before)
                if location.hasNegativeCounter && !location.isSingleCounter && !appSettings.hasSeenNegativeCountExplanation {
                    negativeCountWarningBanner
                }

                // Counter list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Counters")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ForEach(location.counters) { counter in
                        CounterRowView(
                            counter: counter,
                            password: counterPasswords[counter.deviceId],
                            onModifyCount: { onModifyCount(counter) },
                            onViewHistory: { onViewHistory(counter) }
                        )
                        .padding(.horizontal)
                    }
                }

                // View aggregated history button
                if location.counters.count > 1 {
                    Button(action: onViewAggregatedHistory) {
                        HStack {
                            Image(systemName: "chart.bar.xaxis")
                            Text("View Aggregated History")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            // Icon and connection status
            HStack {
                ZStack {
                    Circle()
                        .fill(location.displayColor.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: location.displayIcon)
                        .font(.system(size: 24))
                        .foregroundColor(location.displayColor)
                }

                Spacer()

                // Map status badge
                if location.isOnMap {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.caption)
                        Text("On Map")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.slash")
                            .font(.caption)
                        Text("Local Only")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            // Aggregated count
            HStack(alignment: .firstTextBaseline) {
                Text("\(location.currentCount)")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.primary)

                if let limit = location.overcrowdingLimit {
                    Text("/ \(limit)")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Trend indicator
                if !location.comparisonSymbol.isEmpty {
                    Text(location.comparisonSymbol)
                        .font(.system(size: 28))
                        .foregroundColor(location.comparisonColor)
                        .padding(.leading, 8)
                }

                Spacer()
            }

            // Overcrowding progress bar (if limit set)
            if let limit = location.overcrowdingLimit, limit > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Capacity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int((Double(location.currentCount) / Double(limit)) * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor(for: location.currentCount, limit: limit))
                                .frame(width: min(CGFloat(location.currentCount) / CGFloat(limit) * geometry.size.width, geometry.size.width), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }

            // Counter summary
            HStack {
                Text(location.counterSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // Connection status summary
                connectionStatusSummary
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Negative Count Warning

    private var negativeCountWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Some counters show negative values")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text("This is expected when people enter one door and exit another.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                appSettings.hasSeenNegativeCountExplanation = true
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusSummary: some View {
        let onlineCount = location.counters.filter { $0.connectionStatus == .online }.count
        let totalCount = location.counters.count

        HStack(spacing: 4) {
            Image(systemName: onlineCount == totalCount ? "wifi" : (onlineCount > 0 ? "wifi.exclamationmark" : "wifi.slash"))
                .font(.caption)
                .foregroundColor(onlineCount == totalCount ? .green : (onlineCount > 0 ? .orange : .red))

            Text("\(onlineCount)/\(totalCount) online")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func progressColor(for count: Int, limit: Int) -> Color {
        let percentage = Double(count) / Double(limit)
        if percentage >= 0.9 {
            return .red
        } else if percentage >= 0.7 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LocationDetailView(
                location: CrowdCountLocation(
                    id: "B5678",
                    name: "Central Library",
                    address: "123 Main Street",
                    latitude: 40.7128,
                    longitude: -74.0060,
                    color: "blue",
                    icon: "books.vertical",
                    comparison: "up",
                    counters: [
                        Counter(deviceId: "B5678", label: "Main Entrance", currentCount: 45, overcrowdingLimit: 80, connectionStatus: .online),
                        Counter(deviceId: "C9012", label: "Side Door", currentCount: -3, overcrowdingLimit: 20, connectionStatus: .online),
                        Counter(deviceId: "D3456", label: "Emergency Exit", currentCount: 8, connectionStatus: .offline)
                    ],
                    isOnMap: true
                ),
                counterPasswords: ["B5678": "pass1", "C9012": "pass2", "D3456": "pass3"],
                onModifyCount: { _ in },
                onViewHistory: { _ in },
                onViewAggregatedHistory: {}
            )
            .environmentObject(AppSettings())
        }
    }
}
#endif
