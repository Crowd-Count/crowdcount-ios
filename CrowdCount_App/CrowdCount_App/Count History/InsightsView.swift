import SwiftUI

enum InsightsPeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case year = "Year"
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

    // Entry data (tracks people who entered)
    var entryDayData: [String: Double] = [:]
    var averageEntryDayData: [String: Double]?
    var entryWeekData: [String: Double] = [:]
    var averageEntryWeekData: [String: Double]?
    var entryYearData: [String: Double] = [:]
    var averageEntryYearData: [String: Double]?

    // Dwell time
    var dwellTimeMinutes: Double?
    var dwellTimeWeekData: [String: Double]?
    var dwellTimeYearData: [String: Double]?

    // Date picker data
    var availableDates: [String] = []
    var availableWeeks: [WeekInfo] = []
    var availableYears: [String] = []
    var selectedDay: String = "Today"
    var selectedWeek: WeekInfo? = nil
    var selectedYear: String = "This Year"

    // Date picker callbacks
    var onDaySelected: ((String) -> Void)?
    var onWeekSelected: ((WeekInfo) -> Void)?
    var onYearSelected: ((String) -> Void)?

    // Helper closures for date formatting
    var getCurrentDate: (() -> String)?
    var getCurrentYear: (() -> String)?
    var formattedDateLong: ((String) -> String)?

    // Loading states
    let isDayLoading: Bool
    let isWeekLoading: Bool
    let isYearLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Period Selector - outside ScrollView so always visible
            Picker("Period", selection: $selectedPeriod) {
                ForEach(InsightsPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Date picker (disabled for now)
            // insightsDatePicker
            Spacer().frame(height: 8)

            ScrollView {
                VStack(spacing: 16) {
                    // Content based on selected period
                    switch selectedPeriod {
                case .day:
                    DayInsightsContent(
                        dayData: dayData,
                        averageDayData: averageDayData,
                        entryDayData: entryDayData,
                        averageEntryDayData: averageEntryDayData,
                        dwellTimeMinutes: dwellTimeMinutes,
                        isLoading: isDayLoading
                    )
                case .week:
                    WeekInsightsContent(
                        weekData: weekData,
                        averageWeekData: averageWeekData,
                        entryWeekData: entryWeekData,
                        averageEntryWeekData: averageEntryWeekData,
                        dwellTimeWeekData: dwellTimeWeekData,
                        isLoading: isWeekLoading
                    )
                case .year:
                    YearInsightsContent(
                        yearData: yearData,
                        averageYearData: averageYearData,
                        entryYearData: entryYearData,
                        averageEntryYearData: averageEntryYearData,
                        dwellTimeYearData: dwellTimeYearData,
                        isLoading: isYearLoading
                    )
                }

                    // Info text explaining comparisons
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trend arrows and \"vs Typical\" comparisons are based on historical averages. Entry comparisons are adjusted to match your current progress — only completed \(selectedPeriod == .week ? "days" : selectedPeriod == .year ? "months" : "hours") are fully counted, and the current \(selectedPeriod == .week ? "day is pro-rated by hour" : selectedPeriod == .year ? "month is pro-rated by day" : "data is compared as-is").")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer(minLength: 20)
                }
            }
        }
    }

    // MARK: - Date Picker

    @ViewBuilder
    private var insightsDatePicker: some View {
        switch selectedPeriod {
        case .day:
            if !availableDates.isEmpty {
                Menu {
                    ForEach(availableDates.sorted(by: >), id: \.self) { date in
                        let displayDate = (date == getCurrentDate?()) ? "Today" : (formattedDateLong?(date) ?? date)
                        Button(displayDate) {
                            onDaySelected?(date)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedDay)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        case .week:
            if !availableWeeks.isEmpty {
                Menu {
                    ForEach(availableWeeks) { week in
                        Button(week.label) {
                            onWeekSelected?(week)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedWeek?.label ?? "Select Week")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        case .year:
            if !availableYears.isEmpty {
                Menu {
                    ForEach(availableYears, id: \.self) { year in
                        let displayYear = (year == getCurrentYear?()) ? "This Year" : year
                        Button(displayYear) {
                            onYearSelected?(year)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedYear)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Day Insights Content

struct DayInsightsContent: View {
    let dayData: [String: Double]
    let averageDayData: [String: Double]?
    var entryDayData: [String: Double] = [:]
    var averageEntryDayData: [String: Double]?
    var dwellTimeMinutes: Double?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageDayOccupancy(from: dayData)
    }

    // Only include hours that have data today for fair comparison
    private var relevantHours: Set<String> {
        Set(dayData.filter { $0.value > 0 }.keys)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageDayData else { return nil }
        let filtered = avg.filter { relevantHours.contains($0.key) }
        guard !filtered.isEmpty else { return nil }
        return StatisticsCalculator.averageDayOccupancy(from: filtered)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    private var totalEntries: Int {
        StatisticsCalculator.totalDayEntries(from: entryDayData)
    }

    private var historicalAvgTotalEntries: Int? {
        guard let avg = averageEntryDayData else { return nil }
        let relevantEntryHours = Set(entryDayData.filter { $0.value > 0 }.keys)
        let filtered = avg.filter { relevantEntryHours.contains($0.key) }
        guard !filtered.isEmpty else { return nil }
        let total = StatisticsCalculator.totalDayEntries(from: filtered)
        return total > 0 ? total : nil
    }

    private var entryVsAveragePercentage: Double? {
        guard totalEntries > 0, let historical = historicalAvgTotalEntries else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(totalEntries), average: Double(historical))
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

                // Entries Card
                if totalEntries > 0 {
                    InsightCard(title: "Entries", icon: "person.fill.badge.plus") {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(totalEntries),
                            label: "Total Entries Today",
                            trend: trendDirection(from: entryVsAveragePercentage),
                            trendValue: entryVsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )

                        if let peak = StatisticsCalculator.peakEntryHour(from: entryDayData) {
                            Divider()
                            StatRow(
                                label: "Peak Entry Hour",
                                value: "\(StatisticsCalculator.formatHour(peak.hour)) (\(StatisticsCalculator.formatNumber(peak.count)))"
                            )
                        }

                        if let avg = StatisticsCalculator.avgHourlyEntries(from: entryDayData) {
                            StatRow(
                                label: "Avg Hourly Entries",
                                value: StatisticsCalculator.formatNumber(avg)
                            )
                        }

                        if let busiestWindow = StatisticsCalculator.busiestEntryPeriod(from: entryDayData) {
                            Divider()
                            StatRow(
                                label: "Busiest Window",
                                value: "\(StatisticsCalculator.formatHourRange(start: busiestWindow.startHour, end: busiestWindow.endHour)) (\(StatisticsCalculator.formatNumber(busiestWindow.totalEntries)))"
                            )
                        }
                    }
                }

                // Dwell Time Card
                if let dwell = dwellTimeMinutes, dwell > 0 {
                    InsightCard(title: "Avg Time of Stay", icon: "timer") {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatDwellTime(dwell),
                            label: "Avg Visit Duration"
                        )
                        Text("Estimated from occupancy and entry data")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                        if let entryComp = StatisticsCalculator.entryMorningAfternoonTotals(from: entryDayData) {
                            Divider()
                            ComparisonRow(
                                leftLabel: "Morning Entries",
                                leftValue: StatisticsCalculator.formatNumber(entryComp.morningTotal),
                                rightLabel: "Afternoon Entries",
                                rightValue: StatisticsCalculator.formatNumber(entryComp.afternoonTotal),
                                highlightLeft: entryComp.morningTotal > entryComp.afternoonTotal
                            )
                        }
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

                        if let histEntries = historicalAvgTotalEntries, let entryPct = entryVsAveragePercentage {
                            Divider()
                            StatRow(
                                label: "Entries vs Historical",
                                value: StatisticsCalculator.formatPercentage(entryPct),
                                trend: trendDirection(from: entryPct)
                            )
                            Text("Typical total entries: \(StatisticsCalculator.formatNumber(histEntries))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
    var entryWeekData: [String: Double] = [:]
    var averageEntryWeekData: [String: Double]?
    var dwellTimeWeekData: [String: Double]?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageWeekOccupancy(from: weekData)
    }

    // Only include days that have data in the current week for fair comparison
    private var relevantDays: Set<String> {
        Set(weekData.filter { $0.value > 0 }.keys)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageWeekData else { return nil }
        let filtered = avg.filter { relevantDays.contains($0.key) }
        guard !filtered.isEmpty else { return nil }
        return StatisticsCalculator.averageWeekOccupancy(from: filtered)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    private var totalEntries: Int {
        StatisticsCalculator.totalWeekEntries(from: entryWeekData)
    }

    private var historicalAvgTotalEntries: Int? {
        guard let avg = averageEntryWeekData else { return nil }
        let allDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let calendar = Calendar.current
        let now = Date()
        // weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
        let weekday = calendar.component(.weekday, from: now)
        // Convert to Monday-based index: Mon=0, Tue=1, ..., Sun=6
        let todayIndex = (weekday + 5) % 7
        let currentHour = calendar.component(.hour, from: now)
        let hourFraction = Double(currentHour) / 24.0

        var total: Double = 0
        for (index, day) in allDays.enumerated() {
            guard let historicalValue = avg[day] else { continue }
            if index < todayIndex {
                // Completed day - include fully
                total += historicalValue
            } else if index == todayIndex {
                // Today - pro-rate by hour of day
                total += historicalValue * hourFraction
            }
            // Future days - skip
        }
        let result = Int(total.rounded())
        return result > 0 ? result : nil
    }

    private var entryVsAveragePercentage: Double? {
        guard totalEntries > 0, let historical = historicalAvgTotalEntries else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(totalEntries), average: Double(historical))
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

                // Entries Card
                if totalEntries > 0 {
                    InsightCard(title: "Entries", icon: "person.fill.badge.plus") {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(totalEntries),
                            label: "Total Entries This Week",
                            trend: trendDirection(from: entryVsAveragePercentage),
                            trendValue: entryVsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )

                        if let avg = StatisticsCalculator.avgDailyEntries(from: entryWeekData) {
                            Divider()
                            StatRow(
                                label: "Avg Daily Entries",
                                value: StatisticsCalculator.formatNumber(avg)
                            )
                        }

                        if let busiest = StatisticsCalculator.busiestEntryDay(from: entryWeekData) {
                            StatRow(
                                label: "Most Entries",
                                value: "\(busiest.day) (\(StatisticsCalculator.formatNumber(busiest.totalEntries)))"
                            )
                        }

                        if let slowest = StatisticsCalculator.slowestEntryDay(from: entryWeekData) {
                            StatRow(
                                label: "Fewest Entries",
                                value: "\(slowest.day) (\(StatisticsCalculator.formatNumber(slowest.totalEntries)))"
                            )
                        }
                    }
                }

                // Dwell Time Card
                if let dwellData = dwellTimeWeekData {
                    let daysWithData = dwellData.filter { $0.value > 0 }
                    if !daysWithData.isEmpty {
                        let avgDwell = daysWithData.values.reduce(0, +) / Double(daysWithData.count)
                        InsightCard(title: "Avg Time of Stay", icon: "timer") {
                            LargeStatDisplay(
                                value: StatisticsCalculator.formatDwellTime(avgDwell),
                                label: "Weekly Avg Visit Duration"
                            )

                            if let longest = daysWithData.max(by: { $0.value < $1.value }) {
                                Divider()
                                StatRow(
                                    label: "Longest Stay",
                                    value: "\(longest.key) (\(StatisticsCalculator.formatDwellTime(longest.value)))"
                                )
                            }

                            if let shortest = daysWithData.min(by: { $0.value < $1.value }) {
                                StatRow(
                                    label: "Shortest Stay",
                                    value: "\(shortest.key) (\(StatisticsCalculator.formatDwellTime(shortest.value)))"
                                )
                            }

                            Text("Weekly average estimated from occupancy and entry data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

                        if let entryComp = StatisticsCalculator.entryWeekendWeekdayTotals(from: entryWeekData) {
                            Divider()
                            ComparisonRow(
                                leftLabel: "Weekday Entries",
                                leftValue: StatisticsCalculator.formatNumber(entryComp.weekdayTotal),
                                rightLabel: "Weekend Entries",
                                rightValue: StatisticsCalculator.formatNumber(entryComp.weekendTotal),
                                highlightLeft: entryComp.weekdayTotal > entryComp.weekendTotal
                            )
                        }
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

                        if let histEntries = historicalAvgTotalEntries, let entryPct = entryVsAveragePercentage {
                            Divider()
                            StatRow(
                                label: "Entries vs Historical",
                                value: StatisticsCalculator.formatPercentage(entryPct),
                                trend: trendDirection(from: entryPct)
                            )
                            Text("Typical total entries: \(StatisticsCalculator.formatNumber(histEntries))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
    var entryYearData: [String: Double] = [:]
    var averageEntryYearData: [String: Double]?
    var dwellTimeYearData: [String: Double]?
    let isLoading: Bool

    private var avgOccupancy: Int? {
        StatisticsCalculator.averageYearOccupancy(from: yearData)
    }

    // Only include months that have data in the current year for fair comparison
    private var relevantMonths: Set<String> {
        Set(yearData.filter { $0.value > 0 }.keys)
    }

    private var historicalAvgOccupancy: Int? {
        guard let avg = averageYearData else { return nil }
        let filtered = avg.filter { relevantMonths.contains($0.key) }
        guard !filtered.isEmpty else { return nil }
        return StatisticsCalculator.averageYearOccupancy(from: filtered)
    }

    private var vsAveragePercentage: Double? {
        guard let current = avgOccupancy, let historical = historicalAvgOccupancy else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(current), average: Double(historical))
    }

    private var hasData: Bool {
        avgOccupancy != nil
    }

    private var totalEntries: Int {
        StatisticsCalculator.totalYearEntries(from: entryYearData)
    }

    private var historicalAvgTotalEntries: Int? {
        guard let avg = averageEntryYearData else { return nil }
        let allMonths = ["January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December"]
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now) // 1-based
        let currentDay = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayFraction = Double(currentDay) / Double(daysInMonth)

        var total: Double = 0
        for (index, month) in allMonths.enumerated() {
            guard let historicalValue = avg[month] else { continue }
            let monthNumber = index + 1
            if monthNumber < currentMonth {
                // Completed month - include fully
                total += historicalValue
            } else if monthNumber == currentMonth {
                // Current month - pro-rate by day of month
                total += historicalValue * dayFraction
            }
            // Future months - skip
        }
        let result = Int(total.rounded())
        return result > 0 ? result : nil
    }

    private var entryVsAveragePercentage: Double? {
        guard totalEntries > 0, let historical = historicalAvgTotalEntries else { return nil }
        return StatisticsCalculator.vsAveragePercentage(current: Double(totalEntries), average: Double(historical))
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

                // Entries Card
                if totalEntries > 0 {
                    InsightCard(title: "Entries", icon: "person.fill.badge.plus") {
                        LargeStatDisplay(
                            value: StatisticsCalculator.formatNumber(totalEntries),
                            label: "Total Entries This Year",
                            trend: trendDirection(from: entryVsAveragePercentage),
                            trendValue: entryVsAveragePercentage.map { StatisticsCalculator.formatPercentage($0) }
                        )

                        if let avg = StatisticsCalculator.avgMonthlyEntries(from: entryYearData) {
                            Divider()
                            StatRow(
                                label: "Avg Monthly Entries",
                                value: StatisticsCalculator.formatNumber(avg)
                            )
                        }

                        if let busiest = StatisticsCalculator.busiestEntryMonth(from: entryYearData) {
                            StatRow(
                                label: "Most Entries",
                                value: "\(StatisticsCalculator.abbreviatedMonth(busiest.month)) (\(StatisticsCalculator.formatNumber(busiest.totalEntries)))"
                            )
                        }

                        if let slowest = StatisticsCalculator.slowestEntryMonth(from: entryYearData) {
                            StatRow(
                                label: "Fewest Entries",
                                value: "\(StatisticsCalculator.abbreviatedMonth(slowest.month)) (\(StatisticsCalculator.formatNumber(slowest.totalEntries)))"
                            )
                        }
                    }
                }

                // Dwell Time Card
                if let dwellData = dwellTimeYearData {
                    let monthsWithData = dwellData.filter { $0.value > 0 }
                    if !monthsWithData.isEmpty {
                        let avgDwell = monthsWithData.values.reduce(0, +) / Double(monthsWithData.count)
                        InsightCard(title: "Avg Time of Stay", icon: "timer") {
                            LargeStatDisplay(
                                value: StatisticsCalculator.formatDwellTime(avgDwell),
                                label: "Yearly Avg Visit Duration"
                            )

                            if let longest = monthsWithData.max(by: { $0.value < $1.value }) {
                                Divider()
                                StatRow(
                                    label: "Longest Stay",
                                    value: "\(StatisticsCalculator.abbreviatedMonth(longest.key)) (\(StatisticsCalculator.formatDwellTime(longest.value)))"
                                )
                            }

                            if let shortest = monthsWithData.min(by: { $0.value < $1.value }) {
                                StatRow(
                                    label: "Shortest Stay",
                                    value: "\(StatisticsCalculator.abbreviatedMonth(shortest.key)) (\(StatisticsCalculator.formatDwellTime(shortest.value)))"
                                )
                            }

                            Text("Yearly average estimated from occupancy and entry data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

                        if let histEntries = historicalAvgTotalEntries, let entryPct = entryVsAveragePercentage {
                            Divider()
                            StatRow(
                                label: "Entries vs Historical",
                                value: StatisticsCalculator.formatPercentage(entryPct),
                                trend: trendDirection(from: entryPct)
                            )
                            Text("Previous years entries: \(StatisticsCalculator.formatNumber(histEntries))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
        selectedPeriod: .constant(.day),
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
        dwellTimeMinutes: 42.3,
        isDayLoading: false,
        isWeekLoading: false,
        isYearLoading: false
    )
}
