import SwiftUI

struct CounterRowView: View {
    let counter: Counter
    let password: String?
    let onModifyCount: () -> Void
    let onViewHistory: () -> Void

    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var showNegativeExplanation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: connection status + label
            HStack {
                connectionStatusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(counter.label)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Device: \(counter.deviceId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Count display
            HStack(alignment: .firstTextBaseline) {
                // Count value (orange if negative)
                HStack(spacing: 4) {
                    if counter.isNegative {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.body)
                            .onTapGesture {
                                showNegativeExplanation = true
                            }
                    }

                    Text("\(counter.currentCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(counter.isNegative ? .orange : .primary)
                }

                if let limit = counter.overcrowdingLimit {
                    Text("/ \(limit)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: onModifyCount) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                            Text("Modify")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Button(action: onViewHistory) {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar")
                            Text("History")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
        )
        .alert("Negative Count", isPresented: $showNegativeExplanation) {
            Button("Got it") {
                appSettings.hasSeenNegativeCountExplanation = true
            }
        } message: {
            Text("Negative counts are expected in multi-entrance locations. When someone enters through one door and exits through another, individual counters may show negative values while the location total remains accurate.")
        }
    }

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch counter.connectionStatus {
        case .online:
            Image(systemName: "wifi")
                .foregroundColor(.green)
                .font(.title3)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundColor(.red)
                .font(.title3)
        case .unknown:
            Image(systemName: "wifi")
                .foregroundColor(.gray)
                .font(.title3)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CounterRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Normal counter
            CounterRowView(
                counter: Counter(
                    deviceId: "A1234",
                    label: "Main Entrance",
                    currentCount: 42,
                    overcrowdingLimit: 100,
                    connectionStatus: .online
                ),
                password: "pass123",
                onModifyCount: {},
                onViewHistory: {}
            )

            // Negative counter
            CounterRowView(
                counter: Counter(
                    deviceId: "B5678",
                    label: "South Exit",
                    currentCount: -5,
                    overcrowdingLimit: nil,
                    connectionStatus: .online
                ),
                password: "pass456",
                onModifyCount: {},
                onViewHistory: {}
            )

            // Offline counter
            CounterRowView(
                counter: Counter(
                    deviceId: "C9012",
                    label: "Emergency Exit",
                    currentCount: 8,
                    connectionStatus: .offline
                ),
                password: nil,
                onModifyCount: {},
                onViewHistory: {}
            )
        }
        .padding()
        .environmentObject(AppSettings())
        .previewLayout(.sizeThatFits)
    }
}
#endif
