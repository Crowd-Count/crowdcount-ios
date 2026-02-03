import SwiftUI

// MARK: - Insight Card Container

struct InsightCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String
    let subValue: String?
    let trend: TrendDirection?

    init(label: String, value: String, subValue: String? = nil, trend: TrendDirection? = nil) {
        self.label = label
        self.value = value
        self.subValue = subValue
        self.trend = trend
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .fontWeight(.medium)
                if let subValue = subValue {
                    Text(subValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let trend = trend {
                    TrendIndicator(direction: trend)
                }
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Trend Direction

enum TrendDirection {
    case up
    case down
    case neutral

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }
}

// MARK: - Trend Indicator

struct TrendIndicator: View {
    let direction: TrendDirection

    var body: some View {
        Image(systemName: direction.icon)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(direction.color)
    }
}

// MARK: - Comparison Row

struct ComparisonRow: View {
    let leftLabel: String
    let leftValue: String
    let rightLabel: String
    let rightValue: String
    let highlightLeft: Bool

    init(leftLabel: String, leftValue: String, rightLabel: String, rightValue: String, highlightLeft: Bool = false) {
        self.leftLabel = leftLabel
        self.leftValue = leftValue
        self.rightLabel = rightLabel
        self.rightValue = rightValue
        self.highlightLeft = highlightLeft
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leftLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(leftValue)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(highlightLeft ? .blue : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(rightLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(rightValue)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(!highlightLeft ? .blue : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Large Stat Display

struct LargeStatDisplay: View {
    let value: String
    let label: String
    let trend: TrendDirection?
    let trendValue: String?

    init(value: String, label: String, trend: TrendDirection? = nil, trendValue: String? = nil) {
        self.value = value
        self.label = label
        self.trend = trend
        self.trendValue = trendValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))

                if let trend = trend, let trendValue = trendValue {
                    HStack(spacing: 2) {
                        Text(trendValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TrendIndicator(direction: trend)
                    }
                    .foregroundColor(trend.color)
                }
            }

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Peak Time Row

struct PeakTimeRow: View {
    let label: String
    let timeRange: String
    let percentage: String
    let isPeak: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isPeak ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(timeRange)
                .fontWeight(.medium)

            Spacer()

            Text(percentage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .font(.subheadline)
    }
}

// MARK: - No Data View

struct NoInsightDataView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
    }
}

// MARK: - Loading View

struct InsightsLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading insights...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(25)
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview("Insight Cards") {
    ScrollView {
        VStack(spacing: 16) {
            InsightCard(title: "Summary", icon: "chart.bar.fill") {
                LargeStatDisplay(
                    value: "1,234",
                    label: "Total Today",
                    trend: .up,
                    trendValue: "+12%"
                )

                Divider()

                StatRow(label: "Peak Hour", value: "2pm", subValue: "(156 people)")
            }

            InsightCard(title: "Peak Times", icon: "clock.fill") {
                PeakTimeRow(label: "Busiest", timeRange: "11am - 2pm", percentage: "45%", isPeak: true)
                PeakTimeRow(label: "Slowest", timeRange: "6am - 8am", percentage: "5%", isPeak: false)
            }

            InsightCard(title: "Comparisons", icon: "arrow.left.arrow.right") {
                ComparisonRow(
                    leftLabel: "Morning",
                    leftValue: "523",
                    rightLabel: "Afternoon",
                    rightValue: "711",
                    highlightLeft: false
                )
            }

            NoInsightDataView(message: "Not enough data to calculate insights.\nKeep collecting data!")
        }
        .padding(.vertical)
    }
}
