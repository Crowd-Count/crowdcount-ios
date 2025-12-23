import SwiftUI
import Combine
import Foundation
import UIKit

struct AggregatedHistoricView: View {
    let users: [User]
    @Binding var userPasswords: [UUID: String]

    @State private var selectedDay: String = "Today"
    @State private var selectedWeek: WeekInfo? = nil
    @State private var selectedYear: String = "This Year"
    @State private var availableDates: [String] = []
    @State private var availableWeeks: [WeekInfo] = []
    @State private var availableYears: [String] = []
    @State private var dayData: [String: Double] = [:]
    @State private var averageDayData: [String: Double]?
    @State private var weekData: [String: Double] = [:]
    @State private var averageWeekData: [String: Double]?
    @State private var yearData: [String: Double] = [:]
    @State private var averageYearData: [String: Double]?
    @State private var hasInsufficientYearData: Bool = false
    @State private var hasDataForSelectedDay: Bool = true
    @State private var hasDataForSelectedWeek: Bool = true
    @State private var hasDataForSelectedYear: Bool = true
    @State private var mostRecentDataTime: String? = nil
    @State private var mostRecentWeekDay: String? = nil

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                // Day view
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableDates.sorted(by: >), id: \.self) { date in
                                let displayDate = (date == getCurrentDate()) ? "Today" : formattedDatelong(from: date)
                                Button(displayDate, action: {
                                    selectedDay = displayDate
                                    fetchAggregatedDayData(for: date)
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedDay)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    if hasDataForSelectedDay {
                        BarGraphDay(
                            dayData: dayData,
                            averageDayData: averageDayData,
                            isTodayView: selectedDay == "Today",
                            selectedDate: selectedDay,
                            isDeviceOnline: false, // Aggregated view doesn't show online status
                            mostRecentDataTime: mostRecentDataTime
                        )
                            .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for today")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another day")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(25)
                .padding(.horizontal)

                // Week view
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableWeeks) { week in
                                Button(week.label, action: {
                                    selectedWeek = week
                                    fetchAggregatedWeekData(for: week.startDate)
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedWeek?.label ?? "Select Week")
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    if hasDataForSelectedWeek {
                        BarGraphWeek(
                            weekData: weekData,
                            averageWeekData: averageWeekData ?? [:],
                            selectedDate: selectedWeek?.label ?? ""
                        )
                            .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for this week")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another week")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(30)
                .padding(.horizontal)

                // Year view
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableYears, id: \.self) { year in
                                let displayYear = (year == getCurrentYear()) ? "This Year" : year
                                Button(displayYear, action: {
                                    selectedYear = displayYear
                                    let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                                    fetchAggregatedYearData(for: yearInt)
                                })
                            }
                        } label: {
                            HStack {
                                Text(selectedYear)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    if hasDataForSelectedYear {
                        BarGraphYear(
                            yearData: yearData,
                            averageYearData: averageYearData,
                            selectedYear: selectedYear,
                            hasInsufficientData: hasInsufficientYearData
                        )
                        .frame(height: 250)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .cornerRadius(25)
                            .frame(height: 250)
                            .overlay(
                                VStack {
                                    Text("No data for this year")
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text("Please select another year")
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.1))
                .cornerRadius(30)
                .padding(.horizontal)
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .navigationBarTitle("Aggregated Count History", displayMode: .inline)
        .onAppear {
            fetchAllAvailableDates()
            fetchAggregatedDayData(for: getCurrentDate())
            fetchAggregatedYearData(for: getCurrentYearInt())
        }
    }

    // MARK: - Fetch Available Dates (from all users)
    func fetchAllAvailableDates() {
        var allDates: Set<String> = []
        let group = DispatchGroup()

        for user in users {
            guard let password = userPasswords[user.id] else { continue }
            group.enter()

            guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_user_days") else {
                group.leave()
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let body: [String: Any] = ["device_id": user.userId, "password": password]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decodedResponse = try? JSONDecoder().decode(AvailableDatesResponse.self, from: data) {
                    DispatchQueue.main.async {
                        allDates.formUnion(decodedResponse.dates)
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            // Convert UTC dates from server to local dates for display
            let localDates = TZ.utcDatesToLocalDates(Array(allDates))
            self.availableDates = localDates.sorted(by: >)
            self.availableYears = Array(Set(localDates.map { self.formattedYear(from: $0) })).sorted(by: >)
            self.availableWeeks = self.generateAvailableWeeks(from: localDates)
            if let firstWeek = self.availableWeeks.first {
                self.selectedWeek = firstWeek
                self.fetchAggregatedWeekData(for: firstWeek.startDate)
            }
        }
    }

    // MARK: - Aggregate Day Data
    /// Fetch aggregated day data for a LOCAL date by fetching from the UTC days that cover it
    func fetchAggregatedDayData(for localDate: String) {
        // Get the UTC dates that cover this local day
        let utcDates = TZ.utcDatesForLocalDay(localDate)
        let utcDatesToFetch = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        var aggregatedData: [String: Double] = [:]
        var aggregatedAverageData: [String: Double] = [:]
        var hasAnyData = false
        let group = DispatchGroup()
        let lock = NSLock()

        for user in users {
            guard let password = userPasswords[user.id] else { continue }

            // Fetch day data from each UTC date that covers this local day
            for utcDate in utcDatesToFetch {
                group.enter()

                guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_day_data") else {
                    group.leave()
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                let body: [String: Any] = ["device_id": user.userId, "password": password, "date": utcDate]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                URLSession.shared.dataTask(with: request) { data, response, error in
                    defer { group.leave() }

                    guard let data = data, error == nil else { return }

                    if let decoded = try? JSONDecoder().decode(DayDataResponse.self, from: data) {
                        // Filter and shift bins to only include hours that fall within the target local day
                        let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: decoded.day_data, targetLocalDate: localDate)
                        lock.lock()
                        hasAnyData = hasAnyData || !localBins.isEmpty
                        for (hour, count) in localBins {
                            aggregatedData[hour, default: 0] += count
                        }
                        lock.unlock()
                    }
                }.resume()

                // Also fetch average data for this UTC date
                group.enter()
                guard let avgUrl = URL(string: "\(AppSettings.apiBaseURL)/get_average_day_data") else {
                    group.leave()
                    continue
                }

                var avgRequest = URLRequest(url: avgUrl)
                avgRequest.httpMethod = "POST"
                let avgBody: [String: Any] = ["device_id": user.userId, "password": password, "date": utcDate]
                avgRequest.httpBody = try? JSONSerialization.data(withJSONObject: avgBody)
                avgRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

                URLSession.shared.dataTask(with: avgRequest) { data, response, error in
                    defer { group.leave() }

                    guard let data = data, error == nil else { return }

                    if let decoded = try? JSONDecoder().decode(AverageDayDataResponse.self, from: data) {
                        let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: decoded.average_day_data, targetLocalDate: localDate)
                        lock.lock()
                        for (hour, count) in localBins {
                            aggregatedAverageData[hour, default: 0] += count
                        }
                        lock.unlock()
                    }
                }.resume()
            }
        }

        group.notify(queue: .main) {
            self.hasDataForSelectedDay = hasAnyData
            self.dayData = aggregatedData
            self.averageDayData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
            self.mostRecentDataTime = self.findMostRecentDataTime(in: aggregatedData)
        }
    }

    // MARK: - Aggregate Week Data
    func fetchAggregatedWeekData(for startDate: String) {
        var aggregatedData: [String: Double] = [:]
        var aggregatedAverageData: [String: Double] = [:]
        var hasAnyData = false
        let group = DispatchGroup()

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = formattedDateshort(from: startDate)
        }

        for user in users {
            guard let password = userPasswords[user.id] else { continue }
            group.enter()

            guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_week_data") else {
                group.leave()
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let body: [String: Any] = ["device_id": user.userId, "password": password, "date": formattedStartDate]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(WeekDataResponse.self, from: data) {
                    DispatchQueue.main.async {
                        hasAnyData = true
                        for (day, count) in decoded.week_data {
                            aggregatedData[day, default: 0] += count
                        }
                    }
                }
            }.resume()

            // Also fetch average week data
            group.enter()
            guard let avgUrl = URL(string: "\(AppSettings.apiBaseURL)/get_average_week_data") else {
                group.leave()
                continue
            }

            var avgRequest = URLRequest(url: avgUrl)
            avgRequest.httpMethod = "POST"
            let avgBody: [String: Any] = ["device_id": user.userId, "password": password, "date": formattedStartDate]
            avgRequest.httpBody = try? JSONSerialization.data(withJSONObject: avgBody)
            avgRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: avgRequest) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(AverageWeekDataResponse.self, from: data) {
                    DispatchQueue.main.async {
                        for (day, count) in decoded.average_week_data {
                            aggregatedAverageData[day, default: 0] += count
                        }
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            self.hasDataForSelectedWeek = hasAnyData
            self.weekData = aggregatedData
            self.averageWeekData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
            self.mostRecentWeekDay = self.findMostRecentWeekDay(in: aggregatedData)
        }
    }

    // MARK: - Aggregate Year Data
    func fetchAggregatedYearData(for year: Int) {
        var aggregatedData: [String: Double] = [:]
        var aggregatedAverageData: [String: Double] = [:]
        var hasAnyData = false
        let group = DispatchGroup()

        for user in users {
            guard let password = userPasswords[user.id] else { continue }
            group.enter()

            guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_year_data") else {
                group.leave()
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let body: [String: Any] = ["device_id": user.userId, "password": password, "year": year]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(YearDataResponse.self, from: data) {
                    DispatchQueue.main.async {
                        hasAnyData = true
                        for (month, count) in decoded.year_data {
                            aggregatedData[month, default: 0] += count
                        }
                    }
                }
            }.resume()

            // Also fetch average year data
            group.enter()
            guard let avgUrl = URL(string: "\(AppSettings.apiBaseURL)/get_average_year_data") else {
                group.leave()
                continue
            }

            var avgRequest = URLRequest(url: avgUrl)
            avgRequest.httpMethod = "POST"
            let avgBody: [String: Any] = ["device_id": user.userId, "password": password, "year": year]
            avgRequest.httpBody = try? JSONSerialization.data(withJSONObject: avgBody)
            avgRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: avgRequest) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(AverageYearDataResponse.self, from: data) {
                    DispatchQueue.main.async {
                        switch decoded.average_year_data {
                        case .data(let yearDict):
                            for (month, count) in yearDict {
                                aggregatedAverageData[month, default: 0] += count
                            }
                        case .notAvailable:
                            break
                        }
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            self.hasDataForSelectedYear = hasAnyData
            self.yearData = aggregatedData
            self.averageYearData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
            self.hasInsufficientYearData = aggregatedAverageData.isEmpty
        }
    }

    // MARK: - Helper Functions (copied from HistoricView)
    func findMostRecentDataTime(in data: [String: Double]) -> String? {
        let nonZeroEntries = data.filter { $0.value > 0 }
        guard !nonZeroEntries.isEmpty else { return nil }

        let hourNumbers = nonZeroEntries.keys.compactMap { Int($0) }
        guard let latestHour = hourNumbers.max() else { return nil }

        return String(latestHour)
    }

    func findMostRecentWeekDay(in data: [String: Double]) -> String? {
        let nonZeroEntries = data.filter { $0.value > 0 }
        guard !nonZeroEntries.isEmpty else { return nil }

        let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        for day in dayOrder.reversed() {
            if nonZeroEntries.keys.contains(day) {
                return day
            }
        }

        return nonZeroEntries.keys.first
    }

    // Display: LOCAL "yyyy-MM-dd" → show as local long date (e.g., "January 14, 2024")
    func formattedDatelong(from date: String) -> String {
        TZ.longLocal(fromLocalyyyyMMdd: date)
    }

    // Convert long local label → "yyyy-MM-dd" LOCAL format
    func formattedDateshort(from longDate: String) -> String {
        return TZ.yyyyMMddLocal(fromLongLocal: longDate) ?? longDate
    }

    // Year extraction from LOCAL date string
    func formattedYear(from date: String) -> String {
        guard let d = TZ.localDate(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "yyyy"
        return f.string(from: d)
    }

    func getCurrentYear() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"
        return dateFormatter.string(from: Date())
    }

    func getCurrentYearInt() -> Int {
        return Calendar.current.component(.year, from: Date())
    }

    // Get today's LOCAL date as "yyyy-MM-dd"
    func getCurrentDate() -> String {
        TZ.yyyyMMddLocal(from: Date())
    }

    func getCurrentWeekStartDate() -> String {
        let calendar = Calendar.current
        let currentDate = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: startOfWeek)
    }

    func generateAvailableWeeks(from dates: [String]) -> [WeekInfo] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current  // Dates are now LOCAL dates
        let sortedDates = dates.compactMap { f.date(from: $0) }.sorted(by: >)

        var weeks = [WeekInfo]()
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        var currentWeekStart: Date?
        var currentWeekLabel = "This Week"
        var currentWeekDates = [Date]()

        for date in sortedDates {
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            if currentWeekStart == nil {
                currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
                currentWeekLabel = "This Week"
            }

            if calendar.component(.weekOfYear, from: currentWeekStart!) == weekOfYear {
                currentWeekDates.append(date)
            } else {
                if let startDate = currentWeekStart {
                    weeks.append(WeekInfo(label: currentWeekLabel, startDate: f.string(from: startDate)))
                }
                currentWeekDates.removeAll()
                currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
                currentWeekDates.append(date)
                currentWeekLabel = formattedWeek(from: currentWeekStart!)
            }
        }

        if let startDate = currentWeekStart, !currentWeekDates.isEmpty {
            weeks.append(WeekInfo(label: currentWeekLabel, startDate: f.string(from: startDate)))
        }

        return weeks
    }

    func formattedWeek(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd"
        let startOfWeek = dateFormatter.string(from: date)
        let endOfWeek = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: date)!)
        return "\(startOfWeek) - \(endOfWeek)"
    }
}

struct AggregatedHistoricView_Previews: PreviewProvider {
    static var previews: some View {
        AggregatedHistoricView(users: [], userPasswords: .constant([:]))
    }
}

// MARK: - Time zone & bin-shifting helpers
private enum TZ {
    static let utc = TimeZone(secondsFromGMT: 0)!

    /// Parse a "yyyy-MM-dd" string as a UTC date (midnight UTC on that day)
    static func utcDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    /// Parse a "yyyy-MM-dd" string as a LOCAL date (midnight local on that day)
    static func localDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    /// Format a Date as "yyyy-MM-dd" in UTC timezone
    static func yyyyMMddUTC(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Format a Date as "yyyy-MM-dd" in LOCAL timezone
    static func yyyyMMddLocal(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Display a LOCAL "yyyy-MM-dd" as a long local date string (e.g., "January 14, 2024")
    static func longLocal(fromLocalyyyyMMdd s: String) -> String {
        guard let d = localDate(from: s) else { return s }
        let f = DateFormatter()
        f.timeZone = .current
        f.locale = .current
        f.dateStyle = .long
        return f.string(from: d)
    }

    /// Parse a long local date string back to "yyyy-MM-dd" LOCAL format
    static func yyyyMMddLocal(fromLongLocal longDate: String) -> String? {
        let fIn = DateFormatter()
        fIn.timeZone = .current
        fIn.locale = .current
        fIn.dateStyle = .long
        guard let d = fIn.date(from: longDate) else { return nil }
        return yyyyMMddLocal(from: d)
    }

    /// Given a LOCAL date "yyyy-MM-dd", return the two UTC dates that cover this local day
    static func utcDatesForLocalDay(_ localYYYYMMDD: String) -> (primary: String, secondary: String?) {
        guard let localMidnight = localDate(from: localYYYYMMDD) else {
            return (localYYYYMMDD, nil)
        }

        let utcAtLocalMidnight = yyyyMMddUTC(from: localMidnight)
        let offsetSeconds = TimeZone.current.secondsFromGMT(for: localMidnight)
        let offsetHours = offsetSeconds / 3600

        if offsetHours == 0 {
            return (utcAtLocalMidnight, nil)
        } else if offsetHours < 0 {
            let calendar = Calendar(identifier: .iso8601)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: localMidnight) {
                let nextUTCDate = yyyyMMddUTC(from: nextDay)
                return (utcAtLocalMidnight, nextUTCDate)
            }
            return (utcAtLocalMidnight, nil)
        } else {
            let calendar = Calendar(identifier: .iso8601)
            if let prevDay = calendar.date(byAdding: .day, value: -1, to: localMidnight) {
                let prevUTCDate = yyyyMMddUTC(from: prevDay)
                return (utcAtLocalMidnight, prevUTCDate)
            }
            return (utcAtLocalMidnight, nil)
        }
    }

    /// Shift UTC hour bins to local hours, filtering to only include hours that fall within the target local day
    static func shiftHourlyBinsUTCtoLocal(
        forUTCDate utcYYYYMMDD: String,
        bins: [String: Double],
        targetLocalDate: String
    ) -> [String: Double] {
        guard let utcMidnight = utcDate(from: utcYYYYMMDD),
              let targetLocalMidnight = localDate(from: targetLocalDate) else {
            return [:]
        }

        // IMPORTANT: Use UTC calendar for setting UTC hours
        var utcCalendar = Calendar(identifier: .iso8601)
        utcCalendar.timeZone = utc

        // Use local calendar for converting to local time
        var localCalendar = Calendar(identifier: .iso8601)
        localCalendar.timeZone = .current

        var out: [String: Double] = [:]

        for (hourKey, value) in bins {
            guard let utcHour = Int(hourKey), utcHour >= 0, utcHour < 24 else { continue }

            // Create the actual UTC timestamp for this hour (using UTC calendar!)
            guard let utcTimestamp = utcCalendar.date(bySettingHour: utcHour, minute: 0, second: 0, of: utcMidnight) else {
                continue
            }

            // Convert to local time components
            let localComponents = localCalendar.dateComponents([.year, .month, .day, .hour], from: utcTimestamp)

            // Check if this timestamp falls on our target local day
            let targetComponents = localCalendar.dateComponents([.year, .month, .day], from: targetLocalMidnight)

            if localComponents.year == targetComponents.year &&
               localComponents.month == targetComponents.month &&
               localComponents.day == targetComponents.day {
                if let localHour = localComponents.hour {
                    out[String(localHour), default: 0] += value
                }
            }
        }

        return out
    }

    /// Convert a list of UTC dates to the set of local dates they contribute to.
    /// Filters out any local dates that are in the future (after today).
    static func utcDatesToLocalDates(_ utcDates: [String]) -> [String] {
        var localDatesSet = Set<String>()

        // Get today's local date for filtering
        let todayLocal = yyyyMMddLocal(from: Date())

        for utcDate in utcDates {
            guard let utcMidnight = self.utcDate(from: utcDate) else { continue }

            var localCalendar = Calendar(identifier: .iso8601)
            localCalendar.timeZone = .current

            let localAtUTCMidnight = localCalendar.dateComponents([.year, .month, .day], from: utcMidnight)
            if let y = localAtUTCMidnight.year, let m = localAtUTCMidnight.month, let d = localAtUTCMidnight.day {
                let localDateStr = String(format: "%04d-%02d-%02d", y, m, d)
                // Only add if not in the future
                if localDateStr <= todayLocal {
                    localDatesSet.insert(localDateStr)
                }
            }

            var utcCalendar = Calendar(identifier: .iso8601)
            utcCalendar.timeZone = utc
            if let utcEndOfDay = utcCalendar.date(bySettingHour: 23, minute: 59, second: 0, of: utcMidnight) {
                let localAtUTCEnd = localCalendar.dateComponents([.year, .month, .day], from: utcEndOfDay)
                if let y = localAtUTCEnd.year, let m = localAtUTCEnd.month, let d = localAtUTCEnd.day {
                    let localDateStr = String(format: "%04d-%02d-%02d", y, m, d)
                    // Only add if not in the future
                    if localDateStr <= todayLocal {
                        localDatesSet.insert(localDateStr)
                    }
                }
            }
        }

        return Array(localDatesSet)
    }
}
