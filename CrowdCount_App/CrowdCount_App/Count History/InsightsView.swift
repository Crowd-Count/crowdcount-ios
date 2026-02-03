import SwiftUI

enum InsightsPeriod: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisYear = "This Year"
}

struct InsightsView: View {
    @Binding var selectedPeriod: InsightsPeriod

    // Data from parent view (all values represent AVERAGE OCCUPANCY)
    let dayData: [String: Double]
    let averageDayData: [String: Double]?
    let weekData: [String: Double]
    let averageWeekData: [String: Double]?
    let yearData: [String: Double]
    let averageYearData: [String: Double]?

    // Loading states
    let isDayLoading: Bool
    let isWeekLoading: Bool
    let isYearLoading: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Period Selector
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(InsightsPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content based on selected period
                switch selectedPeriod {
                case .today:
                    DayInsightsContent(
                        dayData: dayData,
                        averageDayData: averageDayData,
                        isLoading: isDayLoading
                    )
                case .thisWeek:
                    WeekInsightsContent(
                        weekData: weekData,
                        averageWeekData: averageWeekData,
                        isLoading: isWeekLoading
                    )
                case .thisYear:
                    YearInsightsContent(
                        yearData: yearData,
                        averageYearData: averageYearData,
                        isLoading: isYearLoading
                    )
                }

                Spacer(minLength: 20)
            }
        }
    }
}

// MARK: - Day Insights Content

struct DayInsightsContent: View {
    let dayData: [String: Double]
    let averageDayData: [String: Double]?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageDayOccupancy(from: dayData)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageDayData else { return nil }
        return StatisticsCalculator.averageDayOccupancy(from: avg)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    var body: some View {
        if isLoading {
            InsightsLoadingView()
        } else if hasData {
            VStack(spacing: 16) {
                // Summary Card
                InsightCard(title: "Summary", icon: "chart.bar.fill") {
                    if let peak = StatisticsCalculator.peakOccupancy(from: dayData) {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(peak.count),
                            label: "Peak Occupancy",
                            trend: trendDirection(from: vsAveragePercentage),
                            trendValue: vsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )

                        Divider()

                        StatRow(
                            label: "Peak Hour",
                            value: StatisticsCalculator.formatHour(peak.hour)
                        )
                    }

                    if let avg = avgOccupancy {
                        StatRow(
                            label: "Avg Occupancy",
                            value: StatisticsCalculator.formatNumber(avg)
                        )
                    }
                }

                // Peak Times Card
                if let busiest = StatisticsCalculator.busiestPeriod(from: dayData) {
                    InsightCard(title: "Peak Times", icon: "clock.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Busiest")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(StatisticsCalculator.formatHourRange(start: busiest.startHour, end: busiest.endHour))
                                    .fontWeight(.medium)
                                Spacer()
                                Text("avg \(busiest.avgOccupancy)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)

                            if let slowest = StatisticsCalculator.slowestPeriod(from: dayData) {
                                HStack {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text("Slowest")
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Text(StatisticsCalculator.formatHourRange(start: slowest.startHour, end: slowest.endHour))
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("avg \(slowest.avgOccupancy)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                // Morning vs Afternoon Card
                if let comparison = StatisticsCalculator.morningAfternoonComparison(from: dayData) {
                    InsightCard(title: "Time of Day", icon: "sun.horizon.fill") {
                        ComparisonRow(
                            leftLabel: "Morning Avg (6am-12pm)",
                            leftValue: StatisticsCalculator.formatNumber(comparison.morningAvg),
                            rightLabel: "Afternoon Avg (12pm-6pm)",
                            rightValue: StatisticsCalculator.formatNumber(comparison.afternoonAvg),
                            highlightLeft: comparison.morningAvg > comparison.afternoonAvg
                        )
                    }
                }

                // Comparison Card
                if let historical = historicalAvgOccupancy, let pct = vsAveragePercentage {
                    InsightCard(title: "vs Typical Day", icon: "arrow.left.arrow.right") {
                        StatRow(
                            label: "vs Historical Average",
                            value: StatisticsCalculator.formatPercentage(pct),
                            trend: trendDirection(from: pct)
                        )
                        Text("Typical avg occupancy: \(StatisticsCalculator.formatNumber(historical))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            NoInsightDataView(message: "No data available for today.\nCheck back once counts are recorded.")
        }
    }
}

// MARK: - Week Insights Content

struct WeekInsightsContent: View {
    let weekData: [String: Double]
    let averageWeekData: [String: Double]?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageWeekOccupancy(from: weekData)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageWeekData else { return nil }
        return StatisticsCalculator.averageWeekOccupancy(from: avg)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    var body: some View {
        if isLoading {
            InsightsLoadingView()
        } else if hasData {
            VStack(spacing: 16) {
                // Summary Card
                InsightCard(title: "Summary", icon: "chart.bar.fill") {
                    if let busiest = StatisticsCalculator.busiestDay(from: weekData) {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(busiest.avgOccupancy),
                            label: "Peak Daily Avg (\(busiest.day))",
                            trend: trendDirection(from: vsAveragePercentage),
                            trendValue: vsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )
                    }

                    if let avg = avgOccupancy {
                        Divider()
                        StatRow(
                            label: "Weekly Avg Occupancy",
                            value: StatisticsCalculator.formatNumber(avg)
                        )
                    }
                }

                // Busiest / Slowest Days Card
                if let busiest = StatisticsCalculator.busiestDay(from: weekData),
                   let slowest = StatisticsCalculator.slowestDay(from: weekData) {
                    InsightCard(title: "Day Performance", icon: "calendar") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Busiest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(busiest.day)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg \(StatisticsCalculator.formatNumber(busiest.avgOccupancy)) people")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                                .frame(height: 50)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text("Slowest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(slowest.day)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg \(StatisticsCalculator.formatNumber(slowest.avgOccupancy)) people")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Weekend vs Weekday Card
                if let comparison = StatisticsCalculator.weekendWeekdayComparison(from: weekData) {
                    InsightCard(title: "Weekend vs Weekday", icon: "calendar.badge.clock") {
                        ComparisonRow(
                            leftLabel: "Weekday Avg",
                            leftValue: StatisticsCalculator.formatNumber(comparison.weekdayAvg),
                            rightLabel: "Weekend Avg",
                            rightValue: StatisticsCalculator.formatNumber(comparison.weekendAvg),
                            highlightLeft: comparison.weekdayAvg > comparison.weekendAvg
                        )
                    }
                }

                // Comparison Card
                if let historical = historicalAvgOccupancy, let pct = vsAveragePercentage {
                    InsightCard(title: "vs Typical Week", icon: "arrow.left.arrow.right") {
                        StatRow(
                            label: "vs Historical Average",
                            value: StatisticsCalculator.formatPercentage(pct),
                            trend: trendDirection(from: pct)
                        )
                        Text("Typical weekly avg: \(StatisticsCalculator.formatNumber(historical))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            NoInsightDataView(message: "No data available for this week.\nCheck back once counts are recorded.")
        }
    }
}

// MARK: - Year Insights Content

struct YearInsightsContent: View {
    let yearData: [String: Double]
    let averageYearData: [String: Double]?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageYearOccupancy(from: yearData)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageYearData else { return nil }
        return StatisticsCalculator.averageYearOccupancy(from: avg)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    var body: some View {
        if isLoading {
            InsightsLoadingView()
        } else if hasData {
            VStack(spacing: 16) {
                // Summary Card
                InsightCard(title: "Summary", icon: "chart.bar.fill") {
                    if let busiest = StatisticsCalculator.busiestMonth(from: yearData) {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(busiest.avgOccupancy),
                            label: "Peak Monthly Avg (\(StatisticsCalculator.abbreviatedMonth(busiest.month)))",
                            trend: trendDirection(from: vsAveragePercentage),
                            trendValue: vsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )
                    }

                    if let avg = avgOccupancy {
                        Divider()
                        StatRow(
                            label: "Yearly Avg Occupancy",
                            value: StatisticsCalculator.formatNumber(avg)
                        )
                    }
                }

                // Busiest / Slowest Months Card
                if let busiest = StatisticsCalculator.busiestMonth(from: yearData),
                   let slowest = StatisticsCalculator.slowestMonth(from: yearData) {
                    InsightCard(title: "Month Performance", icon: "calendar") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Busiest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(StatisticsCalculator.abbreviatedMonth(busiest.month))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg \(StatisticsCalculator.formatNumber(busiest.avgOccupancy)) people")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                                .frame(height: 50)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text("Slowest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(StatisticsCalculator.abbreviatedMonth(slowest.month))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("avg \(StatisticsCalculator.formatNumber(slowest.avgOccupancy)) people")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Comparison Card
                if let historical = historicalAvgOccupancy, let pct = vsAveragePercentage {
                    InsightCard(title: "vs Previous Years", icon: "arrow.left.arrow.right") {
                        StatRow(
                            label: "vs Historical Average",
                            value: StatisticsCalculator.formatPercentage(pct),
                            trend: trendDirection(from: pct)
                        )
                        Text("Previous years avg: \(StatisticsCalculator.formatNumber(historical))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            NoInsightDataView(message: "No data available for this year.\nCheck back once counts are recorded.")
        }
    }
}

// MARK: - Helper

private func trendDirection(from percentage: Double?) -> TrendDirection? {
    guard let pct = percentage else { return nil }
    if pct > 1 {
        return .up
    } else if pct < -1 {
        return .down
    } else {
        return .neutral
    }
}

// MARK: - Preview

#Preview("Insights View") {
    InsightsView(
        selectedPeriod: .constant(.today),
        dayData: [
            "6": 45, "7": 78, "8": 120, "9": 156, "10": 189,
            "11": 210, "12": 198, "13": 220, "14": 185, "15": 167,
            "16": 145, "17": 132, "18": 98, "19": 76, "20": 45
        ],
        averageDayData: [
            "6": 40, "7": 70, "8": 110, "9": 140, "10": 170,
            "11": 190, "12": 180, "13": 200, "14": 170, "15": 155,
            "16": 135, "17": 120, "18": 90, "19": 70, "20": 40
        ],
        weekData: [
            "Monday": 120, "Tuesday": 135, "Wednesday": 145,
            "Thursday": 138, "Friday": 152, "Saturday": 98, "Sunday": 72
        ],
        averageWeekData: [
            "Monday": 115, "Tuesday": 130, "Wednesday": 140,
            "Thursday": 135, "Friday": 148, "Saturday": 95, "Sunday": 70
        ],
        yearData: [
            "January": 95, "February": 102, "March": 118,
            "April": 132, "May": 145, "June": 158
        ],
        averageYearData: [
            "January": 90, "February": 98, "March": 112,
            "April": 125, "May": 140, "June": 152
        ],
        isDayLoading: false,
        isWeekLoading: false,
        isYearLoading: false
    )
}
