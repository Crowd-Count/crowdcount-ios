import Foundation

/// Pure calculation functions for analytics insights
/// Note: All data represents AVERAGE OCCUPANCY (average people present), not cumulative counts
struct StatisticsCalculator {

    // MARK: - Daily Statistics (hourly average occupancy)

    /// Calculate average occupancy across all active hours
    static func averageDayOccupancy(from dayData: [String: Double]) -> Int? {
        let nonZero = dayData.values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return Int(nonZero.reduce(0, +) / Double(nonZero.count))
    }

    /// Find peak occupancy (busiest hour)
    static func peakOccupancy(from dayData: [String: Double]) -> (hour: Int, count: Int)? {
        guard !dayData.isEmpty else { return nil }
        let nonZero = dayData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let maxEntry = nonZero.max(by: { $0.value < $1.value }),
           let hour = Int(maxEntry.key) {
            return (hour, Int(maxEntry.value))
        }
        return nil
    }

    /// Find lowest occupancy hour (with data)
    static func lowestOccupancy(from dayData: [String: Double]) -> (hour: Int, count: Int)? {
        guard !dayData.isEmpty else { return nil }
        let nonZero = dayData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let minEntry = nonZero.min(by: { $0.value < $1.value }),
           let hour = Int(minEntry.key) {
            return (hour, Int(minEntry.value))
        }
        return nil
    }

    /// Calculate percentage difference from average
    static func vsAveragePercentage(current: Double, average: Double) -> Double? {
        guard average > 0 else { return nil }
        return ((current - average) / average) * 100
    }

    /// Calculate morning (6am-12pm) vs afternoon (12pm-6pm) average occupancy
    static func morningAfternoonComparison(from dayData: [String: Double]) -> (morningAvg: Int, afternoonAvg: Int)? {
        var morningValues: [Double] = []
        var afternoonValues: [Double] = []

        for (hourStr, count) in dayData {
            guard let hour = Int(hourStr), count > 0 else { continue }
            if hour >= 6 && hour < 12 {
                morningValues.append(count)
            } else if hour >= 12 && hour < 18 {
                afternoonValues.append(count)
            }
        }

        guard !morningValues.isEmpty || !afternoonValues.isEmpty else { return nil }

        let morningAvg = morningValues.isEmpty ? 0 : Int(morningValues.reduce(0, +) / Double(morningValues.count))
        let afternoonAvg = afternoonValues.isEmpty ? 0 : Int(afternoonValues.reduce(0, +) / Double(afternoonValues.count))

        return (morningAvg, afternoonAvg)
    }

    /// Find the busiest 3-hour window
    static func busiestPeriod(from dayData: [String: Double]) -> (startHour: Int, endHour: Int, avgOccupancy: Int)? {
        guard !dayData.isEmpty else { return nil }

        // Find hours with data
        let nonZeroHours = dayData.filter { $0.value > 0 }.keys.compactMap { Int($0) }.sorted()
        guard nonZeroHours.count >= 3 else { return nil }

        var maxAvg: Double = 0
        var maxStartHour = 0

        for startHour in 0..<22 {
            var windowValues: [Double] = []
            for h in startHour..<min(startHour + 3, 24) {
                if let value = dayData[String(h)], value > 0 {
                    windowValues.append(value)
                }
            }
            guard !windowValues.isEmpty else { continue }
            let windowAvg = windowValues.reduce(0, +) / Double(windowValues.count)
            if windowAvg > maxAvg {
                maxAvg = windowAvg
                maxStartHour = startHour
            }
        }

        guard maxAvg > 0 else { return nil }
        return (maxStartHour, min(maxStartHour + 3, 24), Int(maxAvg))
    }

    /// Find the slowest 3-hour window (within operating hours)
    static func slowestPeriod(from dayData: [String: Double]) -> (startHour: Int, endHour: Int, avgOccupancy: Int)? {
        guard !dayData.isEmpty else { return nil }

        // Find hours with data
        let nonZeroHours = dayData.filter { $0.value > 0 }.keys.compactMap { Int($0) }.sorted()
        guard nonZeroHours.count >= 3 else { return nil }

        let minHour = nonZeroHours.min() ?? 0
        let maxHour = nonZeroHours.max() ?? 23

        var minAvg: Double = Double.infinity
        var minStartHour = minHour

        for startHour in minHour..<max(minHour + 1, maxHour - 1) {
            var windowValues: [Double] = []
            for h in startHour..<min(startHour + 3, maxHour + 1) {
                if let value = dayData[String(h)], value > 0 {
                    windowValues.append(value)
                }
            }
            guard !windowValues.isEmpty else { continue }
            let windowAvg = windowValues.reduce(0, +) / Double(windowValues.count)
            if windowAvg < minAvg {
                minAvg = windowAvg
                minStartHour = startHour
            }
        }

        guard minAvg != Double.infinity else { return nil }
        return (minStartHour, min(minStartHour + 3, 24), Int(minAvg))
    }

    // MARK: - Weekly Statistics (daily average occupancy)

    /// Calculate average occupancy across the week
    static func averageWeekOccupancy(from weekData: [String: Double]) -> Int? {
        let nonZero = weekData.values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return Int(nonZero.reduce(0, +) / Double(nonZero.count))
    }

    /// Find busiest day of the week
    static func busiestDay(from weekData: [String: Double]) -> (day: String, avgOccupancy: Int)? {
        guard !weekData.isEmpty else { return nil }
        let nonZero = weekData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let maxEntry = nonZero.max(by: { $0.value < $1.value }) {
            return (maxEntry.key, Int(maxEntry.value))
        }
        return nil
    }

    /// Find slowest day of the week
    static func slowestDay(from weekData: [String: Double]) -> (day: String, avgOccupancy: Int)? {
        guard !weekData.isEmpty else { return nil }
        let nonZero = weekData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let minEntry = nonZero.min(by: { $0.value < $1.value }) {
            return (minEntry.key, Int(minEntry.value))
        }
        return nil
    }

    /// Calculate weekend vs weekday average occupancy
    static func weekendWeekdayComparison(from weekData: [String: Double]) -> (weekdayAvg: Int, weekendAvg: Int)? {
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        let weekends = ["Saturday", "Sunday"]

        var weekdayValues: [Double] = []
        var weekendValues: [Double] = []

        for (day, count) in weekData {
            guard count > 0 else { continue }
            if weekdays.contains(day) {
                weekdayValues.append(count)
            } else if weekends.contains(day) {
                weekendValues.append(count)
            }
        }

        guard !weekdayValues.isEmpty || !weekendValues.isEmpty else { return nil }

        let weekdayAvg = weekdayValues.isEmpty ? 0 : Int(weekdayValues.reduce(0, +) / Double(weekdayValues.count))
        let weekendAvg = weekendValues.isEmpty ? 0 : Int(weekendValues.reduce(0, +) / Double(weekendValues.count))

        return (weekdayAvg, weekendAvg)
    }

    // MARK: - Yearly Statistics (monthly average occupancy)

    /// Calculate average occupancy across the year
    static func averageYearOccupancy(from yearData: [String: Double]) -> Int? {
        let nonZero = yearData.values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return Int(nonZero.reduce(0, +) / Double(nonZero.count))
    }

    /// Find busiest month of the year
    static func busiestMonth(from yearData: [String: Double]) -> (month: String, avgOccupancy: Int)? {
        guard !yearData.isEmpty else { return nil }
        let nonZero = yearData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let maxEntry = nonZero.max(by: { $0.value < $1.value }) {
            return (maxEntry.key, Int(maxEntry.value))
        }
        return nil
    }

    /// Find slowest month of the year
    static func slowestMonth(from yearData: [String: Double]) -> (month: String, avgOccupancy: Int)? {
        guard !yearData.isEmpty else { return nil }
        let nonZero = yearData.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return nil }

        if let minEntry = nonZero.min(by: { $0.value < $1.value }) {
            return (minEntry.key, Int(minEntry.value))
        }
        return nil
    }

    // MARK: - Helper Functions

    /// Format hour as display string (e.g., "2pm", "11am")
    static func formatHour(_ hour: Int) -> String {
        if hour == 0 {
            return "12am"
        } else if hour < 12 {
            return "\(hour)am"
        } else if hour == 12 {
            return "12pm"
        } else {
            return "\(hour - 12)pm"
        }
    }

    /// Format hour range as display string (e.g., "11am - 2pm")
    static func formatHourRange(start: Int, end: Int) -> String {
        return "\(formatHour(start)) - \(formatHour(end))"
    }

    /// Format percentage with sign
    static func formatPercentage(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded >= 0 {
            return "+\(rounded)%"
        } else {
            return "\(rounded)%"
        }
    }

    /// Format numbers with commas
    static func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Get abbreviated day name
    static func abbreviatedDay(_ day: String) -> String {
        return String(day.prefix(3))
    }

    /// Get abbreviated month name
    static func abbreviatedMonth(_ month: String) -> String {
        return String(month.prefix(3))
    }
}
