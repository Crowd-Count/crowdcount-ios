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
    @State private var isLoading: Bool = false
    @State private var isDayLoading: Bool = false
    @State private var isWeekLoading: Bool = false
    @State private var isYearLoading: Bool = false

    @EnvironmentObject var appSettings: AppSettings

    // Use the shared APIService for optimized networking
    private let apiService = APIService.shared

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

                        Button(action: {
                            downloadAggregatedDayDataAsCSV()
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .offset(y: -3)
                        }
                        .padding()
                    }

                    ZStack {
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

                        if isDayLoading {
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                                .frame(height: 250)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )
                        }
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

                        Button(action: {
                            downloadAggregatedWeekDataAsCSV()
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .offset(y: -3)
                        }
                        .padding()
                    }

                    ZStack {
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

                        if isWeekLoading {
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                                .frame(height: 250)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )
                        }
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

                        Button(action: {
                            downloadAggregatedYearDataAsCSV()
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .offset(y: -3)
                        }
                        .padding()
                    }

                    ZStack {
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

                        if isYearLoading {
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                                .frame(height: 250)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )
                        }
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
            Task {
                await loadInitialData()
            }
        }
    }

    /// Load all initial data in parallel for faster loading
    @MainActor
    private func loadInitialData() async {
        isLoading = true
        isDayLoading = true
        isYearLoading = true

        // Fetch all available dates first
        await fetchAllAvailableDatesAsync()

        // Then fetch day and year data in parallel
        async let dayTask: () = fetchAggregatedDayDataAsync(for: getCurrentDate())
        async let yearTask: () = fetchAggregatedYearDataAsync(for: getCurrentYearInt())

        await dayTask
        await yearTask

        isLoading = false
    }

    // MARK: - Fetch Available Dates (from all users)
    func fetchAllAvailableDates() {
        Task {
            await fetchAllAvailableDatesAsync()
        }
    }

    @MainActor
    func fetchAllAvailableDatesAsync() async {
        // Build user list with passwords
        let userList = users.compactMap { user -> (deviceId: String, password: String)? in
            guard let password = userPasswords[user.id] else { return nil }
            return (deviceId: user.userId, password: password)
        }

        // Fetch all dates in parallel using the optimized APIService
        let allDates = await apiService.fetchAllAvailableDates(users: userList)

        // Convert UTC dates from server to local dates for display
        let localDates = TZHelper.utcDatesToLocalDates(allDates)
        self.availableDates = localDates.sorted(by: >)
        self.availableYears = Array(Set(localDates.map { self.formattedYear(from: $0) })).sorted(by: >)
        self.availableWeeks = self.generateAvailableWeeks(from: localDates)

        if let firstWeek = self.availableWeeks.first {
            self.selectedWeek = firstWeek
            await fetchAggregatedWeekDataAsync(for: firstWeek.startDate)
        }
    }

    // MARK: - Aggregate Day Data
    /// Fetch aggregated day data for a LOCAL date by fetching from the UTC days that cover it
    func fetchAggregatedDayData(for localDate: String) {
        Task {
            await fetchAggregatedDayDataAsync(for: localDate)
        }
    }

    @MainActor
    func fetchAggregatedDayDataAsync(for localDate: String) async {
        isDayLoading = true
        defer { isDayLoading = false }

        // Get the UTC dates that cover this local day
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesToFetch = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        // Build user list with passwords
        let userList = users.compactMap { user -> (deviceId: String, password: String)? in
            guard let password = userPasswords[user.id] else { return nil }
            return (deviceId: user.userId, password: password)
        }

        // Fetch all data in parallel using the optimized APIService
        let (aggregatedData, aggregatedAverageData) = await apiService.fetchAggregatedDayData(
            users: userList,
            utcDates: utcDatesToFetch,
            targetLocalDate: localDate
        )

        self.hasDataForSelectedDay = !aggregatedData.isEmpty
        self.dayData = aggregatedData
        self.averageDayData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
        self.mostRecentDataTime = self.findMostRecentDataTime(in: aggregatedData)
    }

    // MARK: - Aggregate Week Data
    func fetchAggregatedWeekData(for startDate: String) {
        Task {
            await fetchAggregatedWeekDataAsync(for: startDate)
        }
    }

    @MainActor
    func fetchAggregatedWeekDataAsync(for startDate: String) async {
        isWeekLoading = true
        defer { isWeekLoading = false }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = formattedDateshort(from: startDate)
        }

        // Build user list with passwords
        let userList = users.compactMap { user -> (deviceId: String, password: String)? in
            guard let password = userPasswords[user.id] else { return nil }
            return (deviceId: user.userId, password: password)
        }

        // Fetch all data in parallel using the optimized APIService
        let (aggregatedData, aggregatedAverageData) = await apiService.fetchAggregatedWeekData(
            users: userList,
            date: formattedStartDate
        )

        self.hasDataForSelectedWeek = !aggregatedData.isEmpty
        self.weekData = aggregatedData
        self.averageWeekData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
        self.mostRecentWeekDay = self.findMostRecentWeekDay(in: aggregatedData)
    }

    // MARK: - Aggregate Year Data
    func fetchAggregatedYearData(for year: Int) {
        Task {
            await fetchAggregatedYearDataAsync(for: year)
        }
    }

    @MainActor
    func fetchAggregatedYearDataAsync(for year: Int) async {
        isYearLoading = true
        defer { isYearLoading = false }

        // Build user list with passwords
        let userList = users.compactMap { user -> (deviceId: String, password: String)? in
            guard let password = userPasswords[user.id] else { return nil }
            return (deviceId: user.userId, password: password)
        }

        // Fetch all data in parallel using the optimized APIService
        let (aggregatedData, aggregatedAverageData) = await apiService.fetchAggregatedYearData(
            users: userList,
            year: year
        )

        self.hasDataForSelectedYear = !aggregatedData.isEmpty
        self.yearData = aggregatedData
        self.averageYearData = aggregatedAverageData
        self.hasInsufficientYearData = aggregatedAverageData == nil
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
        guard let d = TZHelper.localDate(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = .current
        f.locale = .current
        f.dateStyle = .long
        return f.string(from: d)
    }

    // Convert long local label → "yyyy-MM-dd" LOCAL format
    func formattedDateshort(from longDate: String) -> String {
        let fIn = DateFormatter()
        fIn.timeZone = .current
        fIn.locale = .current
        fIn.dateStyle = .long
        guard let d = fIn.date(from: longDate) else { return longDate }
        return TZHelper.yyyyMMddLocal(from: d)
    }

    // Year extraction from LOCAL date string
    func formattedYear(from date: String) -> String {
        guard let d = TZHelper.localDate(from: date) else { return date }
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
        TZHelper.yyyyMMddLocal(from: Date())
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

    // MARK: - Download Functions

    func downloadAggregatedDayDataAsCSV() {
        guard !dayData.isEmpty else {
            print("No day data available to download")
            return
        }

        var csvContent = "Hour,Aggregated Total,Aggregated Average\n"

        // Hours 0-23
        for hour in 0..<24 {
            let hourKey = String(hour)
            let aggregatedCount = dayData[hourKey] ?? 0
            let average = averageDayData?[hourKey]
            let averageString = average != nil ? String(format: "%.1f", average!) : ""
            csvContent += "\(hour),\(String(format: "%.1f", aggregatedCount)),\(averageString)\n"
        }

        guard let csvData = csvContent.data(using: .utf8) else {
            print("Failed to convert CSV to data")
            return
        }

        let dateValue = selectedDay == "Today" ? getCurrentDate() : formattedDateshort(from: selectedDay)
        let fileName = "aggregated_day_\(dateValue)_\(users.count)_counters.csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    func downloadAggregatedWeekDataAsCSV() {
        guard !weekData.isEmpty else {
            print("No week data available to download")
            return
        }

        let weekdayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        var csvContent = "Day,Aggregated Total,Aggregated Average\n"

        for day in weekdayOrder {
            let count = weekData[day] ?? 0
            let average = averageWeekData?[day]
            let averageString = average != nil ? String(format: "%.1f", average!) : ""
            csvContent += "\(day),\(String(format: "%.1f", count)),\(averageString)\n"
        }

        guard let csvData = csvContent.data(using: .utf8) else {
            print("Failed to convert CSV to data")
            return
        }

        let weekLabel = selectedWeek?.startDate ?? "unknown"
        let fileName = "aggregated_week_\(weekLabel)_\(users.count)_counters.csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    func downloadAggregatedYearDataAsCSV() {
        guard !yearData.isEmpty else {
            print("No year data available to download")
            return
        }

        let monthOrder = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

        var csvContent = "Month,Aggregated Total,Aggregated Average\n"

        for month in monthOrder {
            if let count = yearData[month] {
                let average = averageYearData?[month]
                let averageString = average != nil ? String(format: "%.1f", average!) : ""
                csvContent += "\(month),\(String(format: "%.1f", count)),\(averageString)\n"
            }
        }

        guard let csvData = csvContent.data(using: .utf8) else {
            print("Failed to convert CSV to data")
            return
        }

        let yearValue = selectedYear == "This Year" ? getCurrentYear() : selectedYear
        let fileName = "aggregated_year_\(yearValue)_\(users.count)_counters.csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }
}

struct AggregatedHistoricView_Previews: PreviewProvider {
    static var previews: some View {
        AggregatedHistoricView(users: [], userPasswords: .constant([:]))
    }
}

// Note: TZ helper functions are now shared via TZHelper in APIService.swift
