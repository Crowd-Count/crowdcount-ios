import SwiftUI
import Combine
import Foundation
import UIKit

// Data Model for the API Response
struct AvailableDatesResponse: Decodable {
    let dates: [String]
}

// Define a data model to store the day's data
struct DayDataResponse: Decodable {
    let day_data: [String: Double]
}

// Define a data model to store the average day's data
struct AverageDayDataResponse: Decodable {
    let average_day_data: [String: Double]
}

// Define a data model to store the week's data
struct WeekDataResponse: Decodable {
    let week_data: [String: Double]
}

// Define a data model to store the average week's data
struct AverageWeekDataResponse: Decodable {
    let average_week_data: [String: Double]
}

// NEW: Define data models for year data
struct YearDataResponse: Decodable {
    let year_data: [String: Double]
}

struct AverageYearDataResponse: Decodable {
    let average_year_data: AverageYearDataValue
}

// NEW: Handle both dictionary and "N/A" string responses
enum AverageYearDataValue: Decodable {
    case data([String: Double])
    case notAvailable(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let dataDict = try? container.decode([String: Double].self) {
            self = .data(dataDict)
        } else if let naString = try? container.decode(String.self) {
            self = .notAvailable(naString)
        } else {
            throw DecodingError.typeMismatch(AverageYearDataValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected dictionary or string"))
        }
    }
}

struct ConnectionStatusResponse: Decodable {
    let status: String
}

struct WeekInfo: Identifiable {
    var id = UUID()
    var label: String
    var startDate: String
}

struct CSVData: Identifiable {
    var id = UUID()
    var time: String
    var count: Int
}

struct HistoricView: View {
    let userId: String
    let userUUID: UUID
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
    @State private var isDeviceOnline: Bool = false
    @State private var hasDataForSelectedDay: Bool = true
    @State private var hasDataForSelectedWeek: Bool = true
    @State private var hasDataForSelectedYear: Bool = true
    @State private var mostRecentDataTime: String? = nil
    @State private var mostRecentWeekDay: String? = nil
    @State private var isLoading: Bool = false
    @State private var isDayLoading: Bool = false
    @State private var isWeekLoading: Bool = false
    @State private var isYearLoading: Bool = false

    // Auto-refresh timer for live data (30 seconds)
    @State private var refreshTimer: Timer? = nil
    private let refreshInterval: TimeInterval = 30.0

    @EnvironmentObject var appSettings: AppSettings

    // Use the shared APIService for optimized networking with caching
    private let apiService = APIService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                // Day view with chart and download button
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableDates.sorted(by: >), id: \.self) { date in
                                let displayDate = (date == getCurrentDate()) ? "Today" : formattedDatelong(from: date)
                                Button(displayDate, action: {
                                    selectedDay = displayDate
                                    checkAndFetchDayData(for: date)
                                    if date == getCurrentDate() {
                                        fetchConnectionStatus()
                                    }
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
                            checkAndDownloadData(for: selectedDay, period: "day")
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
                                isDeviceOnline: isDeviceOnline,
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
                            RoundedRectangle(cornerRadius: 10)
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
                .id("dayView")

                // Weekly chart view with download button
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableWeeks) { week in
                                Button(week.label, action: {
                                    selectedWeek = week
                                    checkAndFetchWeekData(for: week.startDate)
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
                            downloadWeekDataAsCSV()
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
                            RoundedRectangle(cornerRadius: 10)
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
                .id("weekView")

                // UPDATED: Yearly chart view with actual functionality
                VStack {
                    HStack {
                        Menu {
                            ForEach(availableYears, id: \.self) { year in
                                let displayYear = (year == getCurrentYear()) ? "This Year" : year
                                Button(displayYear, action: {
                                    selectedYear = displayYear
                                    let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                                    fetchYearData(for: yearInt)
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
                            downloadYearDataAsCSV()
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
                            RoundedRectangle(cornerRadius: 10)
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
                .id("yearView")
// Removed entirely for now, not needed, keeping here though in case I want to bring it back
//                VStack {
//                    Text("Issues with this page?")
//                        .bold()
//                        .foregroundColor(.primary)
//                        .padding(10)
//                    Text("We're still working on this, so feel free to report anything by sending us a message!")
//                        .foregroundColor(.secondary)
//                        .multilineTextAlignment(.center)
//                    Text("help@crowdcount.tech")
//                        .font(.body)
//                        .padding()
//                        .onTapGesture {
//                            if let url = URL(string: "mailto:help@crowdcount.tech") {
//                                UIApplication.shared.open(url)
//                            }
//                        }
//
//                }
//                .padding()
//                .background(Color.primary.opacity(0.1))
//                .cornerRadius(30)
//                .padding(.horizontal)
//                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .navigationBarTitle("Count History", displayMode: .inline)
        .onAppear {
            Task {
                await loadInitialData()
            }
            startAutoRefreshTimer()
        }
        .onDisappear {
            stopAutoRefreshTimer()
        }
        .onChange(of: selectedDay) { _, newValue in
            // Restart timer when switching days - only auto-refresh for "Today"
            if newValue == "Today" {
                startAutoRefreshTimer()
            } else {
                stopAutoRefreshTimer()
            }
        }
    }

    // MARK: - Auto-Refresh Timer

    private func startAutoRefreshTimer() {
        // Only auto-refresh when viewing "Today"
        guard selectedDay == "Today" else { return }

        stopAutoRefreshTimer() // Stop any existing timer first

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in
                await refreshTodayData()
            }
        }
    }

    private func stopAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @MainActor
    private func refreshTodayData() async {
        // Silently refresh today's data and connection status
        // Cache TTL is 30 seconds so data will be fresh

        // Refresh connection status
        await fetchConnectionStatusAsync()

        // Refresh day data using the existing method (cache will have expired)
        await checkAndFetchDayDataAsync(for: getCurrentDate())
    }

    /// Load all initial data in parallel for faster loading
    @MainActor
    private func loadInitialData() async {
        isLoading = true
        isDayLoading = true
        isYearLoading = true

        // Fetch available dates first
        await fetchAvailableDatesAsync()

        // Then fetch day data, year data, and connection status in parallel
        async let dayTask: () = checkAndFetchDayDataAsync(for: getCurrentDate())
        async let yearTask: () = fetchYearDataAsync(for: getCurrentYearInt())
        async let statusTask: () = fetchConnectionStatusAsync()

        await dayTask
        await yearTask
        await statusTask

        isLoading = false
    }

    private func viewContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
            content()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                .padding(.bottom)
        }
        .padding()
    }

    func fetchAvailableDates() {
        Task {
            await fetchAvailableDatesAsync()
        }
    }

    @MainActor
    func fetchAvailableDatesAsync() async {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        do {
            let dates = try await apiService.fetchAvailableDates(deviceId: userId, password: password)

            // Convert UTC dates from server to local dates for display
            let localDates = TZHelper.utcDatesToLocalDates(dates)
            self.availableDates = localDates.sorted(by: >)
            self.availableYears = Array(Set(localDates.map { self.formattedYear(from: $0) })).sorted(by: >)
            self.availableWeeks = self.generateAvailableWeeks(from: localDates)

            if let firstWeek = self.availableWeeks.first {
                self.selectedWeek = firstWeek
                await checkAndFetchWeekDataAsync(for: firstWeek.startDate)
            }
        } catch {
            print("Failed to fetch available dates: \(error)")
        }
    }

    // Function to fetch year data
    func fetchYearData(for year: Int) {
        Task {
            await fetchYearDataAsync(for: year)
        }
    }

    @MainActor
    func fetchYearDataAsync(for year: Int) async {
        isYearLoading = true
        defer { isYearLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        do {
            // Fetch year data and average data in parallel
            async let yearTask = apiService.fetchYearData(deviceId: userId, password: password, year: year)
            async let avgTask = apiService.fetchAverageYearData(deviceId: userId, password: password, year: year)

            let yearDataResult = try await yearTask
            let avgDataResult = try? await avgTask

            self.yearData = yearDataResult
            self.hasDataForSelectedYear = !yearDataResult.isEmpty
            self.averageYearData = avgDataResult
            self.hasInsufficientYearData = avgDataResult == nil
        } catch {
            print("Failed to fetch year data: \(error)")
            self.hasDataForSelectedYear = false
            self.averageYearData = nil
            self.hasInsufficientYearData = true
        }
    }

    func checkAndFetchDayData(for date: String) {
        Task {
            await checkAndFetchDayDataAsync(for: date)
        }
    }

    @MainActor
    func checkAndFetchDayDataAsync(for date: String) async {
        isDayLoading = true
        defer { isDayLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        // Convert display string to LOCAL date format
        let localDate = (date == "Today") ? getCurrentDate() : formattedDateshort(from: date)

        // Get the UTC dates that cover this local day
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesToFetch = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        // Use the APIService batch operation to fetch all data in parallel
        let userList = [(deviceId: userId, password: password)]
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

    /// Fetch data for a LOCAL day by fetching from the UTC days that cover it and combining the results
    func fetchDayData(forLocalDate localDate: String) {
        guard let password = userPasswords[userUUID] else {
            print("fetchDayData: missing password for user \(userUUID)")
            return
        }

        // Get the UTC dates that cover this local day
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)

        let group = DispatchGroup()
        var combinedBins: [String: Double] = [:]
        let lock = NSLock()

        // Fetch primary UTC date
        group.enter()
        fetchUTCDayData(utcDate: utcDates.primary, localDate: localDate, password: password) { bins in
            if let bins = bins {
                lock.lock()
                for (hour, count) in bins {
                    combinedBins[hour, default: 0] += count
                }
                lock.unlock()
            }
            group.leave()
        }

        // Fetch secondary UTC date if it exists
        if let secondary = utcDates.secondary {
            group.enter()
            fetchUTCDayData(utcDate: secondary, localDate: localDate, password: password) { bins in
                if let bins = bins {
                    lock.lock()
                    for (hour, count) in bins {
                        combinedBins[hour, default: 0] += count
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }

        // When both fetches complete, update the UI
        group.notify(queue: .main) {
            self.dayData = combinedBins
            self.mostRecentDataTime = self.findMostRecentDataTime(in: combinedBins)

            if combinedBins.isEmpty {
                self.hasDataForSelectedDay = false
            }
        }

        // Also fetch average data
        fetchAverageDayData(forLocalDate: localDate, password: password)
    }

    /// Helper to fetch a single UTC day's data and filter to the target local day
    private func fetchUTCDayData(utcDate: String, localDate: String, password: String, completion: @escaping ([String: Double]?) -> Void) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_day_data") else {
            print("fetchUTCDayData: bad URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": utcDate]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("fetchUTCDayData: network error for \(utcDate):", error.localizedDescription)
                completion(nil)
                return
            }
            guard let data = data else {
                print("fetchUTCDayData: empty response for \(utcDate)")
                completion(nil)
                return
            }

            do {
                let decoded = try JSONDecoder().decode(DayDataResponse.self, from: data)
                // Filter and shift bins to only include hours that fall within the target local day
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: decoded.day_data, targetLocalDate: localDate)
                completion(localBins)
            } catch {
                print("fetchUTCDayData: decode error for \(utcDate):", error)
                completion(nil)
            }
        }.resume()
    }


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

    /// Fetch average day bins for a LOCAL date by fetching from the UTC days that cover it
    func fetchAverageDayData(forLocalDate localDate: String, password: String) {
        // Get the UTC dates that cover this local day
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)

        let group = DispatchGroup()
        var combinedBins: [String: Double] = [:]
        let lock = NSLock()

        // Fetch primary UTC date
        group.enter()
        fetchUTCAverageDayData(utcDate: utcDates.primary, localDate: localDate, password: password) { bins in
            if let bins = bins {
                lock.lock()
                for (hour, count) in bins {
                    combinedBins[hour, default: 0] += count
                }
                lock.unlock()
            }
            group.leave()
        }

        // Fetch secondary UTC date if it exists
        if let secondary = utcDates.secondary {
            group.enter()
            fetchUTCAverageDayData(utcDate: secondary, localDate: localDate, password: password) { bins in
                if let bins = bins {
                    lock.lock()
                    for (hour, count) in bins {
                        combinedBins[hour, default: 0] += count
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.averageDayData = combinedBins.isEmpty ? nil : combinedBins
        }
    }

    /// Helper to fetch average data for a single UTC day
    private func fetchUTCAverageDayData(utcDate: String, localDate: String, password: String, completion: @escaping ([String: Double]?) -> Void) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_average_day_data") else {
            print("fetchUTCAverageDayData: bad URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": utcDate]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("fetchUTCAverageDayData: network error for \(utcDate):", error.localizedDescription)
                completion(nil)
                return
            }
            guard let data = data else {
                print("fetchUTCAverageDayData: empty response for \(utcDate)")
                completion(nil)
                return
            }

            do {
                let decoded = try JSONDecoder().decode(AverageDayDataResponse.self, from: data)
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: decoded.average_day_data, targetLocalDate: localDate)
                completion(localBins)
            } catch {
                print("fetchUTCAverageDayData: decode error for \(utcDate):", error)
                completion(nil)
            }
        }.resume()
    }


    func checkAndFetchWeekData(for startDate: String) {
        Task {
            await checkAndFetchWeekDataAsync(for: startDate)
        }
    }

    @MainActor
    func checkAndFetchWeekDataAsync(for startDate: String) async {
        isWeekLoading = true
        defer { isWeekLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = formattedDateshort(from: startDate)
        }

        // Use the APIService batch operation to fetch all data in parallel
        let userList = [(deviceId: userId, password: password)]
        let (aggregatedData, aggregatedAverageData) = await apiService.fetchAggregatedWeekData(
            users: userList,
            date: formattedStartDate
        )

        self.hasDataForSelectedWeek = !aggregatedData.isEmpty
        self.weekData = aggregatedData
        self.averageWeekData = aggregatedAverageData.isEmpty ? nil : aggregatedAverageData
        self.mostRecentWeekDay = self.findMostRecentWeekDay(in: aggregatedData)
    }

    func getCurrentWeekStartDate() -> String {
        let calendar = Calendar.current
        let currentDate = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: startOfWeek)
    }

    func fetchWeekData(for date: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_week_data") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": date]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to fetch week data: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(WeekDataResponse.self, from: data)
                DispatchQueue.main.async {
                    self.weekData = decodedResponse.week_data
                    self.mostRecentWeekDay = self.findMostRecentWeekDay(in: decodedResponse.week_data)
                    print("Parsed weekData: \(self.weekData)")
                    print("Most recent week day: \(String(describing: self.mostRecentWeekDay))")
                }
            } catch {
                print("Failed to decode week data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
            }
        }.resume()

        fetchAverageWeekData(for: date, password: password)
    }

    func fetchAverageWeekData(for date: String, password: String) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/get_average_week_data") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": date]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to fetch average week data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
                return
            }

            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(AverageWeekDataResponse.self, from: data)
                DispatchQueue.main.async {
                    self.averageWeekData = decodedResponse.average_week_data
                    print("Parsed averageWeekData: \(String(describing: self.averageWeekData))")
                }
            } catch {
                print("Failed to decode average week data: \(error.localizedDescription)")
                if let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) {
                    print("Error response: \(errorResponse)")
                }
                DispatchQueue.main.async {
                    self.averageWeekData = nil
                }
            }
        }.resume()
    }

    func fetchConnectionStatus() {
        Task {
            await fetchConnectionStatusAsync()
        }
    }

    @MainActor
    func fetchConnectionStatusAsync() async {
        do {
            let status = try await apiService.checkConnectionStatus(deviceId: userId)
            self.isDeviceOnline = status == "online"
        } catch {
            print("Failed to fetch connection status: \(error)")
            self.isDeviceOnline = false
        }
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

    // NEW: Helper functions for year handling
    func getCurrentYear() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"
        return dateFormatter.string(from: Date())
    }

    func getCurrentYearInt() -> Int {
        return Calendar.current.component(.year, from: Date())
    }

    func compareMonths(_ lhs: String, _ rhs: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        if let lhsDate = dateFormatter.date(from: lhs), let rhsDate = dateFormatter.date(from: rhs) {
            return lhsDate > rhsDate
        }
        return lhs > rhs
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

    // Get today's LOCAL date as "yyyy-MM-dd"
    func getCurrentDate() -> String {
        TZHelper.yyyyMMddLocal(from: Date())
    }

    func checkAndDownloadData(for date: String, period: String) {
        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        // Convert display string to LOCAL date format
        let localDate = (date == "Today") ? getCurrentDate() : formattedDateshort(from: date)

        // Get the UTC dates that cover this local day
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)

        guard let url = URL(string: "\(AppSettings.apiBaseURL)/check_if_user_has_day") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": utcDates.primary]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to check data availability: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("Raw JSON response: \(jsonResponse)")

                    if let hasData = jsonResponse["has_day"] as? Bool {
                        if hasData {
                            // Use UTC primary date for download (server stores by UTC)
                            self.downloadData(for: utcDates.primary, localDate: localDate, period: period, password: password)
                        } else {
                            print("No data available for the selected date.")
                        }
                    } else {
                        print("Key 'has_data' not found in the response.")
                    }
                } else {
                    print("Failed to parse JSON response")
                }
            } catch {
                print("Failed to parse response: \(error.localizedDescription)")
            }
        }.resume()
    }

    func downloadData(for utcDate: String, localDate: String, period: String, password: String) {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/export_csv") else { return }

        switch period {
        case "day", "week":
            break
        case "year":
            print("Year data export is not yet implemented")
            return
        default:
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["device_id": userId, "password": password, "date": utcDate]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let downloadTask = URLSession.shared.downloadTask(with: request) { tempLocalUrl, response, error in
            if let error = error {
                print("Failed to download data: \(error.localizedDescription)")
                return
            }

            guard let tempLocalUrl = tempLocalUrl else {
                print("No URL for downloaded file")
                return
            }

            DispatchQueue.main.async {
                do {
                    let fileData = try Data(contentsOf: tempLocalUrl)
                    // Use local date for filename so user sees their local date
                    let fileName = "user_\(self.userId)_data_\(localDate).csv"

                    if let topController = UIApplication.shared.topViewController() {
                        presentShareSheet(data: fileData, fileName: fileName, from: topController)
                    }
                } catch {
                    print("Failed to read downloaded file: \(error.localizedDescription)")
                }
            }
        }
        downloadTask.resume()
    }

    func downloadWeekDataAsCSV() {
        guard !weekData.isEmpty else {
            print("No week data available to download")
            return
        }

        // Define the correct weekday order
        let weekdayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        // Build CSV content
        var csvContent = "Day,Count,Average\n"

        for day in weekdayOrder {
            let count = weekData[day] ?? 0
            let average = averageWeekData?[day]
            let averageString = average != nil ? String(format: "%.1f", average!) : ""
            csvContent += "\(day),\(String(format: "%.1f", count)),\(averageString)\n"
        }

        // Convert to Data
        guard let csvData = csvContent.data(using: .utf8) else {
            print("Failed to convert CSV to data")
            return
        }

        // Generate filename using week start date
        let weekLabel = selectedWeek?.startDate ?? "unknown"
        let fileName = "user_\(userId)_week_\(weekLabel).csv"

        // Present share sheet
        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    func downloadYearDataAsCSV() {
        guard !yearData.isEmpty else {
            print("No year data available to download")
            return
        }

        // Define the correct month order
        let monthOrder = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

        // Build CSV content
        var csvContent = "Month,Count,Average\n"

        for month in monthOrder {
            if let count = yearData[month] {
                let average = averageYearData?[month]
                let averageString = average != nil ? String(format: "%.1f", average!) : ""
                csvContent += "\(month),\(String(format: "%.1f", count)),\(averageString)\n"
            }
        }

        // Convert to Data
        guard let csvData = csvContent.data(using: .utf8) else {
            print("Failed to convert CSV to data")
            return
        }

        // Generate filename using year
        let yearValue = selectedYear == "This Year" ? getCurrentYear() : selectedYear
        let fileName = "user_\(userId)_year_\(yearValue).csv"

        // Present share sheet
        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return UIApplication.shared.topViewController() ?? UIViewController()
    }
}

extension UIApplication {
    func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .filter({ $0.activationState == .foregroundActive })
        .map({ $0 as? UIWindowScene })
        .compactMap({ $0 })
        .first?.windows
        .filter({ $0.isKeyWindow }).first?.rootViewController) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

// Note: TZ helper functions are now shared via TZHelper in APIService.swift

// MARK: - Preview

#Preview("Historic View") {
    NavigationView {
        HistoricView(
            userId: "Demo",
            userUUID: UUID(),
            userPasswords: .constant([UUID(): "password"])
        )
        .environmentObject(AppSettings())
    }
}
