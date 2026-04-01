import SwiftUI

// MARK: - POS Sales Summary Card

/// Shows revenue, transaction count, and avg transaction for a period with trend arrows.
struct POSSalesSummaryCard: View {
    let current: POSPeriodStats
    let previous: POSPeriodStats
    let periodLabel: String

    private var revenueTrend: TrendDirection? {
        trendFor(current: current.revenue, previous: previous.revenue)
    }

    private var revenueTrendValue: String? {
        POSFormatting.trendPercentage(current: current.revenue, previous: previous.revenue)
            .map { StatisticsCalculator.formatPercentage($0) }
    }

    private var txTrend: TrendDirection? {
        trendFor(current: current.transactions, previous: previous.transactions)
    }

    private var txTrendValue: String? {
        POSFormatting.trendPercentage(current: current.transactions, previous: previous.transactions)
            .map { StatisticsCalculator.formatPercentage($0) }
    }

    var body: some View {
        InsightCard(title: "\(periodLabel) Sales", icon: "dollarsign.circle.fill") {
            LargeStatDisplay(
                value: POSFormatting.formatCurrency(current.revenue, currency: current.currency),
                label: "Total Revenue",
                trend: revenueTrend,
                trendValue: revenueTrendValue
            )

            Divider()

            StatRow(
                label: "Transactions",
                value: StatisticsCalculator.formatNumber(current.transactions),
                trend: txTrend
            )

            StatRow(
                label: "Avg Transaction",
                value: POSFormatting.formatCurrency(current.avgTransaction, currency: current.currency)
            )
        }
    }

    private func trendFor(current: Int, previous: Int) -> TrendDirection? {
        guard previous > 0 else { return nil }
        let pct = Double(current - previous) / Double(previous) * 100
        if pct > 1 { return .up }
        if pct < -1 { return .down }
        return .neutral
    }
}

// MARK: - POS Conversion Card

/// Shows conversion rate and revenue per visitor.
struct POSConversionCard: View {
    let current: POSPeriodStats
    let previous: POSPeriodStats
    let periodLabel: String

    private var conversionTrend: TrendDirection? {
        guard previous.conversionRate > 0 else { return nil }
        let diff = current.conversionRate - previous.conversionRate
        if diff > 1 { return .up }
        if diff < -1 { return .down }
        return .neutral
    }

    var body: some View {
        InsightCard(title: "\(periodLabel) Conversion", icon: "arrow.triangle.2.circlepath") {
            LargeStatDisplay(
                value: String(format: "%.1f%%", current.conversionRate),
                label: "Conversion Rate",
                trend: conversionTrend
            )

            Divider()

            StatRow(
                label: "Revenue per Visitor",
                value: POSFormatting.formatCurrency(current.revenuePerVisitor, currency: current.currency)
            )

            if current.entries > 0 {
                StatRow(
                    label: "Total Visitors",
                    value: StatisticsCalculator.formatNumber(current.entries)
                )
            }
        }
    }
}

// MARK: - POS Placeholder (Greyed-out cards with unlock overlay)

/// Shows greyed-out POS cards with a "Connect POS to unlock" overlay, matching the web.
struct POSPlaceholderCards: View {
    var onConnect: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Greyed-out placeholder cards with dashes
            VStack(spacing: 16) {
                placeholderConversionCard
                placeholderSalesCard
            }
            .opacity(0.4)
            .allowsHitTesting(false)

            // Unlock overlay — always shown
            Button {
                onConnect?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .font(.caption)
                    Text("Connect a POS system to unlock")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemBackground).opacity(0.9))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
            }
        }
    }

    private var placeholderSalesCard: some View {
        InsightCard(title: "Sales", icon: "dollarsign.circle.fill") {
            LargeStatDisplay(value: "—", label: "Total Revenue")
            Divider()
            StatRow(label: "Transactions", value: "—")
            StatRow(label: "Avg Transaction", value: "—")
        }
    }

    private var placeholderConversionCard: some View {
        InsightCard(title: "Conversion", icon: "arrow.triangle.2.circlepath") {
            StatRow(label: "Conversion Rate", value: "—")
            StatRow(label: "Revenue per Visitor", value: "—")
            StatRow(label: "Total Visitors", value: "—")
        }
    }
}

// MARK: - POS Insights Section

/// Renders the full POS insights section for a given period.
struct POSInsightsSection: View {
    let posInsights: POSInsightsResponse?
    let period: InsightsPeriod
    let hasPOS: Bool
    var onConnectPOS: (() -> Void)? = nil

    private var currentStats: POSPeriodStats? {
        guard let insights = posInsights else { return nil }
        switch period {
        case .day: return insights.today
        case .week: return insights.week
        case .year: return insights.year
        }
    }

    private var previousStats: POSPeriodStats? {
        guard let insights = posInsights else { return nil }
        switch period {
        case .day: return insights.prevDay
        case .week: return insights.prevWeek
        case .year: return insights.prevYear
        }
    }

    private var periodLabel: String {
        switch period {
        case .day: return "Today's"
        case .week: return "This Week's"
        case .year: return "This Year's"
        }
    }

    var body: some View {
        if !hasPOS {
            POSPlaceholderCards(onConnect: onConnectPOS)
        } else if let current = currentStats, let previous = previousStats, current.transactions > 0 {
            VStack(spacing: 16) {
                if current.entries > 0 {
                    POSConversionCard(
                        current: current,
                        previous: previous,
                        periodLabel: periodLabel
                    )
                }

                POSSalesSummaryCard(
                    current: current,
                    previous: previous,
                    periodLabel: periodLabel
                )
            }
        }
    }
}
