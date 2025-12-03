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
        .environment(\.colorScheme, appSettings.isDarkMode ? .dark : .light)
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

            var urlComponents = URLComponents(string: "\(AppSettings.apiBaseURL)/get_user_days")!
            urlComponents.queryItems = [
                URLQueryItem(name: "user_id", value: user.userId),
                URLQueryItem(name: "password", value: password)
            ]

            guard let url = urlComponents.url else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
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
            self.availableDates = Array(allDates).sorted(by: >)
            self.availableYears = Array(Set(allDates.map { formattedYear(from: $0) })).sorted(by: >)
            self.availableWeeks = generateAvailableWeeks(from: Array(allDates))
            if let firstWeek = self.availableWeeks.first {
                self.selectedWeek = firstWeek
                self.fetchAggregatedWeekData(for: firstWeek.startDate)
            }
        }
    }

    // MARK: - Aggregate Day Data
    func fetchAggregatedDayData(for date: String) {
        var aggregatedData: [String: Double] = [:]
        var aggregatedAverageData: [String: Double] = [:]
        var hasAnyData = false
        let group = DispatchGroup()

        for user in users {
            guard let password = userPasswords[user.id] else { continue }
            group.enter()

            let urlString = "\(AppSettings.apiBaseURL)/get_day_data?user_id=\(user.userId)&password=\(password)&date=\(date)"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(DayDataResponse.self, from: data) {
                    let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: date, bins: decoded.day_data)
                    DispatchQueue.main.async {
                        hasAnyData = true
                        for (hour, count) in localBins {
                            aggregatedData[hour, default: 0] += count
                        }
                    }
                }
            }.resume()

            // Also fetch average data
            group.enter()
            let avgUrlString = "\(AppSettings.apiBaseURL)/get_average_day_data?user_id=\(user.userId)&password=\(password)&date=\(date)"
            guard let avgUrl = URL(string: avgUrlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: avgUrl) { data, response, error in
                defer { group.leave() }

                guard let data = data, error == nil else { return }

                if let decoded = try? JSONDecoder().decode(AverageDayDataResponse.self, from: data) {
                    let localBins = TZ.shiftHourlyBinsUTCtoLocal(forUTCDate: date, bins: decoded.average_day_data)
                    DispatchQueue.main.async {
                        for (hour, count) in localBins {
                            aggregatedAverageData[hour, default: 0] += count
                        }
                    }
                }
            }.resume()
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

            let urlString = "\(AppSettings.apiBaseURL)/get_week_data?user_id=\(user.userId)&password=\(password)&date=\(formattedStartDate)"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
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
            let avgUrlString = "\(AppSettings.apiBaseURL)/get_average_week_data?user_id=\(user.userId)&password=\(password)&date=\(formattedStartDate)"
            guard let avgUrl = URL(string: avgUrlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: avgUrl) { data, response, error in
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

            let urlString = "\(AppSettings.apiBaseURL)/get_year_data?user_id=\(user.userId)&password=\(password)&year=\(year)"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
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
            let avgUrlString = "\(AppSettings.apiBaseURL)/get_average_year_data?user_id=\(user.userId)&password=\(password)&year=\(year)"
            guard let avgUrl = URL(string: avgUrlString) else {
                group.leave()
                continue
            }

            URLSession.shared.dataTask(with: avgUrl) { data, response, error in
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

    func formattedDatelong(from date: String) -> String {
        TZ.longLocal(fromUTCyyyyMMdd: date)
    }

    func formattedDateshort(from longDate: String) -> String {
        let fIn = DateFormatter()
        fIn.timeZone = .current
        fIn.locale   = .current
        fIn.dateStyle = .long
        guard let d = fIn.date(from: longDate) else { return longDate }
        return TZ.yyyyMMddUTC(from: d)
    }

    func formattedYear(from date: String) -> String {
        guard let d = TZ.utcDate(from: date) else { return date }
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

    func getCurrentDate() -> String {
        TZ.yyyyMMddUTC(from: Date())
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
        f.timeZone = TZ.utc
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

    static func utcDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    static func yyyyMMddUTC(from localDate: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: localDate)
    }

    static func longLocal(fromUTCyyyyMMdd s: String) -> String {
        guard let d = utcDate(from: s) else { return s }
        let f = DateFormatter()
        f.timeZone = .current
        f.locale = .current
        f.dateStyle = .long
        return f.string(from: d)
    }

    // Shift 0..23 UTC hourly bins into local 0..23 bins for the *same calendar slot*.
    // (Counts that would spill across day edges are rotated; server-side re-aggregation
    // would be needed for perfect day-boundary semantics.)
    static func shiftHourlyBinsUTCtoLocal(forUTCDate yyyyMMdd: String,
                                          bins: [String: Double]) -> [String: Double] {
        guard let d = utcDate(from: yyyyMMdd) else { return bins }
        let offsetHours = TimeZone.current.secondsFromGMT(for: d) / 3600  // DST-aware
        var out: [String: Double] = [:]
        for (k, v) in bins {
            guard let h = Int(k) else { continue }
            var localH = (h + offsetHours) % 24
            if localH < 0 { localH += 24 }
            out[String(localH), default: 0] += v
        }
        return out
    }
}
