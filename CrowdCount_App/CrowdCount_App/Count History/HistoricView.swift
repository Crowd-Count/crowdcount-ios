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

// Entry data response models (entries track people who entered, not population)
struct EntryDayDataResponse: Decodable {
    let entry_day_data: [String: Double]
}

struct AverageEntryDayDataResponse: Decodable {
    let average_entry_day_data: [String: Double]
}

struct EntryWeekDataResponse: Decodable {
    let entry_week_data: [String: Double]
}

struct AverageEntryWeekDataResponse: Decodable {
    let average_entry_week_data: [String: Double]
}

struct EntryYearDataResponse: Decodable {
    let entry_year_data: [String: Double]
}

struct AverageEntryYearDataResponse: Decodable {
    let average_entry_year_data: [String: Double]
}

// Data type toggle for graphs
enum GraphDataType: String, CaseIterable {
    case population = "Population"
    case entries = "Entries"
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

enum HistoricViewTab: String, CaseIterable {
    case historicCounts = "Historic Counts"
    case insights = "Insights"
}

struct HistoricView: View {
    let userId: String
    let userUUID: UUID
    @Binding var userPasswords: [UUID: String]
    @State private var selectedTab: HistoricViewTab = .historicCounts
    @State private var selectedInsightsPeriod: InsightsPeriod = .today
    @State private var selectedGraphDataType: GraphDataType = .population
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

    // Entry data (tracks people who entered, not population)
    @State private var entryDayData: [String: Double] = [:]
    @State private var averageEntryDayData: [String: Double]?
    @State private var entryWeekData: [String: Double] = [:]
    @State private var averageEntryWeekData: [String: Double]?
    @State private var entryYearData: [String: Double] = [:]
    @State private var averageEntryYearData: [String: Double]?
    @State private var hasDataForSelectedDayEntries: Bool = true
    @State private var hasDataForSelectedWeekEntries: Bool = true
    @State private var hasDataForSelectedYearEntries: Bool = true
    @State private var isEntryDayLoading: Bool = false
    @State private var isEntryWeekLoading: Bool = false
    @State private var isEntryYearLoading: Bool = false

    // Separate data for Insights (always today/this week/this year)
    @State private var insightsTodayData: [String: Double] = [:]
    @State private var insightsTodayAverage: [String: Double]?
    @State private var insightsThisWeekData: [String: Double] = [:]
    @State private var insightsThisWeekAverage: [String: Double]?
    @State private var insightsThisYearData: [String: Double] = [:]
    @State private var insightsThisYearAverage: [String: Double]?
    @State private var insightsEntryTodayData: [String: Double] = [:]
    @State private var insightsEntryThisWeekData: [String: Double] = [:]
    @State private var insightsEntryThisYearData: [String: Double] = [:]
    @State private var insightsAvgEntryTodayData: [String: Double]?
    @State private var insightsAvgEntryThisWeekData: [String: Double]?
    @State private var insightsAvgEntryThisYearData: [String: Double]?
    @State private var insightsInitialLoadComplete: Bool = false
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
        VStack(spacing: 0) {
            // Tab Picker
            Picker("View", selection: $selectedTab) {
                ForEach(HistoricViewTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if selectedTab == .historicCounts {
                VStack(spacing: 0) {
                    // Data type picker (Population vs Entries) - directly in body like InsightsView
                    Picker("Data Type", selection: $selectedGraphDataType) {
                        ForEach(GraphDataType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .onChange(of: selectedGraphDataType) { _, newValue in
                        if newValue == .entries {
                            Task {
                                await fetchEntryDataForCurrentSelections()
                            }
                        }
                    }

                    HistoricCountsContentView(
                        selectedGraphDataType: $selectedGraphDataType,
                        selectedDay: $selectedDay,
                        availableDates: availableDates,
                        dayData: dayData,
                        averageDayData: averageDayData,
                        hasDataForSelectedDay: hasDataForSelectedDay,
                        isDayLoading: isDayLoading,
                        isDeviceOnline: isDeviceOnline,
                        mostRecentDataTime: mostRecentDataTime,
                        entryDayData: entryDayData,
                        averageEntryDayData: averageEntryDayData,
                        hasDataForSelectedDayEntries: hasDataForSelectedDayEntries,
                        isEntryDayLoading: isEntryDayLoading,
                        selectedWeek: $selectedWeek,
                        availableWeeks: availableWeeks,
                        weekData: weekData,
                        averageWeekData: averageWeekData,
                        hasDataForSelectedWeek: hasDataForSelectedWeek,
                        isWeekLoading: isWeekLoading,
                        entryWeekData: entryWeekData,
                        averageEntryWeekData: averageEntryWeekData,
                        hasDataForSelectedWeekEntries: hasDataForSelectedWeekEntries,
                        isEntryWeekLoading: isEntryWeekLoading,
                        selectedYear: $selectedYear,
                        availableYears: availableYears,
                        yearData: yearData,
                        averageYearData: averageYearData,
                        hasDataForSelectedYear: hasDataForSelectedYear,
                        isYearLoading: isYearLoading,
                        hasInsufficientYearData: hasInsufficientYearData,
                        entryYearData: entryYearData,
                        averageEntryYearData: averageEntryYearData,
                        hasDataForSelectedYearEntries: hasDataForSelectedYearEntries,
                        isEntryYearLoading: isEntryYearLoading,
                        onDaySelected: { date in
                            let displayDate = (date == getCurrentDate()) ? "Today" : formattedDatelong(from: date)
                            selectedDay = displayDate
                            checkAndFetchDayData(for: date)
                            if selectedGraphDataType == .entries {
                                Task {
                                    await fetchEntryDayDataAsync(for: date)
                                }
                            }
                            if date == getCurrentDate() {
                                fetchConnectionStatus()
                            }
                        },
                        onWeekSelected: { week in
                            selectedWeek = week
                            checkAndFetchWeekData(for: week.startDate)
                            if selectedGraphDataType == .entries {
                                Task {
                                    await fetchEntryWeekDataAsync(for: week.startDate)
                                }
                            }
                        },
                        onYearSelected: { year in
                            let displayYear = (year == getCurrentYear()) ? "This Year" : year
                            selectedYear = displayYear
                            let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                            fetchYearData(for: yearInt)
                            if selectedGraphDataType == .entries {
                                Task {
                                    await fetchEntryYearDataAsync(for: yearInt)
                                }
                            }
                        },
                        onDownloadDay: {
                            checkAndDownloadData(for: selectedDay, period: "day")
                        },
                        onDownloadWeek: {
                            downloadWeekDataAsCSV()
                        },
                        onDownloadYear: {
                            downloadYearDataAsCSV()
                        },
                        getCurrentDate: getCurrentDate,
                        getCurrentYear: getCurrentYear,
                        formattedDateLong: formattedDatelong,
                        findMostRecentDataTime: findMostRecentDataTime
                    )
                }
            } else {
                InsightsView(
                    selectedPeriod: $selectedInsightsPeriod,
                    dayData: insightsTodayData,
                    averageDayData: insightsTodayAverage,
                    weekData: insightsThisWeekData,
                    averageWeekData: insightsThisWeekAverage,
                    yearData: insightsThisYearData,
                    averageYearData: insightsThisYearAverage,
                    entryDayData: insightsEntryTodayData,
                    averageEntryDayData: insightsAvgEntryTodayData,
                    entryWeekData: insightsEntryThisWeekData,
                    averageEntryWeekData: insightsAvgEntryThisWeekData,
                    entryYearData: insightsEntryThisYearData,
                    averageEntryYearData: insightsAvgEntryThisYearData,
                    isDayLoading: !insightsInitialLoadComplete,
                    isWeekLoading: !insightsInitialLoadComplete,
                    isYearLoading: !insightsInitialLoadComplete
                )
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .navigationBarTitle("Count Analytics", displayMode: .inline)
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
        // Silently refresh today's data in the background (no loading indicators)

        // Refresh connection status
        await fetchConnectionStatusAsync()

        // Silently fetch fresh data without setting loading flags
        guard let password = userPasswords[userUUID] else { return }
        let userList = [(deviceId: userId, password: password)]

        // Fetch today's data silently
        let utcDates = TZHelper.utcDatesForLocalDay(getCurrentDate())
        let utcDatesToFetch = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])
        let (newDayData, newAvgDayData) = await apiService.fetchAggregatedDayData(
            users: userList,
            utcDates: utcDatesToFetch,
            targetLocalDate: getCurrentDate()
        )

        // Update the data silently
        if selectedDay == "Today" {
            dayData = newDayData
            averageDayData = newAvgDayData.isEmpty ? nil : newAvgDayData
            mostRecentDataTime = findMostRecentDataTime(in: newDayData)
        }

        // Always update insights data for today
        insightsTodayData = newDayData
        insightsTodayAverage = newAvgDayData.isEmpty ? nil : newAvgDayData
    }

    /// Load all initial data in parallel for faster loading
    @MainActor
    private func loadInitialData() async {
        isLoading = true
        isDayLoading = true
        isWeekLoading = true
        isYearLoading = true

        // Fetch available dates first
        await fetchAvailableDatesAsync()

        // Then fetch day data, week data, year data, entry data, and connection status in parallel
        async let dayTask: () = checkAndFetchDayDataAsync(for: getCurrentDate())
        async let weekTask: () = checkAndFetchWeekDataAsync(for: getCurrentWeekStartDate())
        async let yearTask: () = fetchYearDataAsync(for: getCurrentYearInt())
        async let entryDayTask: () = fetchEntryDayDataAsync(for: getCurrentDate())
        async let entryWeekTask: () = fetchEntryWeekDataAsync(for: getCurrentWeekStartDate())
        async let entryYearTask: () = fetchEntryYearDataAsync(for: getCurrentYearInt())
        async let statusTask: () = fetchConnectionStatusAsync()

        await dayTask
        await weekTask
        await yearTask
        await entryDayTask
        await entryWeekTask
        await entryYearTask
        await statusTask

        // Store current data for Insights (always today/this week/this year)
        insightsTodayData = dayData
        insightsTodayAverage = averageDayData
        insightsThisWeekData = weekData
        insightsThisWeekAverage = averageWeekData
        insightsThisYearData = yearData
        insightsThisYearAverage = averageYearData
        insightsEntryTodayData = entryDayData
        insightsEntryThisWeekData = entryWeekData
        insightsEntryThisYearData = entryYearData
        insightsAvgEntryTodayData = averageEntryDayData
        insightsAvgEntryThisWeekData = averageEntryWeekData
        insightsAvgEntryThisYearData = averageEntryYearData

        insightsInitialLoadComplete = true
        isLoading = false
    }

    // MARK: - Entry Data Fetching

    /// Fetch entry data for all current selections when switching to entries view
    @MainActor
    private func fetchEntryDataForCurrentSelections() async {
        // Capture values on main actor before async let
        let dayDate = selectedDay == "Today" ? getCurrentDate() : formattedDateshort(from: selectedDay)
        let weekStartDate = selectedWeek?.startDate ?? getCurrentWeekStartDate()
        let yearInt = selectedYear == "This Year" ? getCurrentYearInt() : Int(selectedYear) ?? getCurrentYearInt()

        async let dayTask: () = fetchEntryDayDataAsync(for: dayDate)
        async let weekTask: () = fetchEntryWeekDataAsync(for: weekStartDate)
        async let yearTask: () = fetchEntryYearDataAsync(for: yearInt)

        await dayTask
        await weekTask
        await yearTask
    }

    @MainActor
    private func fetchEntryDayDataAsync(for date: String) async {
        isEntryDayLoading = true
        defer { isEntryDayLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let localDate = (date == getCurrentDate()) ? getCurrentDate() : date
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesToFetch = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        let userList = [(deviceId: userId, password: password)]
        let (aggregatedData, aggregatedAvgData) = await apiService.fetchAggregatedEntryDayData(
            users: userList,
            utcDates: utcDatesToFetch,
            targetLocalDate: localDate
        )

        self.hasDataForSelectedDayEntries = !aggregatedData.isEmpty
        self.entryDayData = aggregatedData
        self.averageEntryDayData = aggregatedAvgData.isEmpty ? nil : aggregatedAvgData
    }

    @MainActor
    private func fetchEntryWeekDataAsync(for startDate: String) async {
        isEntryWeekLoading = true
        defer { isEntryWeekLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = startDate
        }

        let userList = [(deviceId: userId, password: password)]
        let (aggregatedData, aggregatedAvgData) = await apiService.fetchAggregatedEntryWeekData(
            users: userList,
            date: formattedStartDate
        )

        self.hasDataForSelectedWeekEntries = !aggregatedData.isEmpty
        self.entryWeekData = aggregatedData
        self.averageEntryWeekData = aggregatedAvgData.isEmpty ? nil : aggregatedAvgData
    }

    @MainActor
    private func fetchEntryYearDataAsync(for year: Int) async {
        isEntryYearLoading = true
        defer { isEntryYearLoading = false }

        guard let password = userPasswords[userUUID] else {
            print("Password not found for user \(userUUID)")
            return
        }

        let userList = [(deviceId: userId, password: password)]
        let (aggregatedData, aggregatedAvgData) = await apiService.fetchAggregatedEntryYearData(
            users: userList,
            year: year
        )

        self.hasDataForSelectedYearEntries = !aggregatedData.isEmpty
        self.entryYearData = aggregatedData
        self.averageEntryYearData = aggregatedAvgData.isEmpty ? nil : aggregatedAvgData
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
        let weekdayOrder: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

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
        let monthOrder: [String] = ["January", "February", "March", "April", "May", "June",
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

/// A self-contained preview wrapper that renders HistoricCountsContentView
/// with fake data so all three charts (day/week/year) display without an API.
private struct HistoricViewPreview: View {
    @State private var selectedTab: HistoricViewTab = .historicCounts
    @State private var selectedGraphDataType: GraphDataType = .population
    @State private var selectedDay: String = "Today"
    @State private var selectedWeek: WeekInfo? = WeekInfo(label: "This Week", startDate: "2026-01-26")
    @State private var selectedYear: String = "This Year"
    @State private var selectedInsightsPeriod: InsightsPeriod = .today

    // Restaurant day data — lunch rush 12-2pm, tapering by 4pm (data stops at 16 = "now")
    static let fakeDayData: [String: Double] = [
        "11": 12, "12": 58, "13": 72, "14": 45, "15": 28, "16": 22
    ]
    // 8-week daily average shows full day pattern including dinner rush
    static let fakeAvgDayData: [String: Double] = [
        "11": 15, "12": 62, "13": 68, "14": 48, "15": 30, "16": 24,
        "17": 32, "18": 55, "19": 74, "20": 65, "21": 38, "22": 12
    ]

    // Restaurant week data — busier Thu-Sat, quieter early week
    static let fakeWeekData: [String: Double] = [
        "Monday": 95, "Tuesday": 110, "Wednesday": 125,
        "Thursday": 155, "Friday": 210, "Saturday": 235, "Sunday": 180
    ]
    static let fakeAvgWeekData: [String: Double] = [
        "Monday": 90, "Tuesday": 105, "Wednesday": 120,
        "Thursday": 148, "Friday": 200, "Saturday": 225, "Sunday": 170
    ]

    // Restaurant year data — summer patio season peak, holiday bumps
    static let fakeYearData: [String: Double] = [
        "January": 2800, "February": 2600
    ]
    static let fakeAvgYearData: [String: Double] = [
        "January": 2900, "February": 2750, "March": 3400,
        "April": 3800, "May": 4500, "June": 5200,
        "July": 5600, "August": 5400, "September": 4800,
        "October": 4100, "November": 3500, "December": 3900
    ]

    // Entry data (total guests seated throughout the day, higher than concurrent occupancy)
    static let fakeEntryDayData: [String: Double] = [
        "11": 18, "12": 85, "13": 96, "14": 62, "15": 38, "16": 30
    ]
    static let fakeEntryWeekData: [String: Double] = [
        "Monday": 160, "Tuesday": 185, "Wednesday": 210,
        "Thursday": 260, "Friday": 350, "Saturday": 390, "Sunday": 300
    ]
    static let fakeEntryYearData: [String: Double] = [
        "January": 4600, "February": 4300
    ]

    static let fakeAvailableDates: [String] = [
        "2026-02-04", "2026-02-03", "2026-02-02", "2026-02-01",
        "2026-01-31", "2026-01-30", "2026-01-29", "2026-01-28"
    ]
    static let fakeAvailableWeeks: [WeekInfo] = [
        WeekInfo(label: "This Week", startDate: "2026-01-26"),
        WeekInfo(label: "Jan 19 - Jan 25", startDate: "2026-01-19"),
        WeekInfo(label: "Jan 12 - Jan 18", startDate: "2026-01-12")
    ]
    static let fakeAvailableYears: [String] = ["2026", "2025"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    ForEach(HistoricViewTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if selectedTab == .historicCounts {
                    VStack(spacing: 0) {
                        Picker("Data Type", selection: $selectedGraphDataType) {
                            ForEach(GraphDataType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                        HistoricCountsContentView(
                            selectedGraphDataType: $selectedGraphDataType,
                            selectedDay: $selectedDay,
                            availableDates: Self.fakeAvailableDates,
                            dayData: Self.fakeDayData,
                            averageDayData: Self.fakeAvgDayData,
                            hasDataForSelectedDay: true,
                            isDayLoading: false,
                            isDeviceOnline: true,
                            mostRecentDataTime: "16",
                            entryDayData: Self.fakeEntryDayData,
                            averageEntryDayData: nil,
                            hasDataForSelectedDayEntries: true,
                            isEntryDayLoading: false,
                            selectedWeek: $selectedWeek,
                            availableWeeks: Self.fakeAvailableWeeks,
                            weekData: Self.fakeWeekData,
                            averageWeekData: Self.fakeAvgWeekData,
                            hasDataForSelectedWeek: true,
                            isWeekLoading: false,
                            entryWeekData: Self.fakeEntryWeekData,
                            averageEntryWeekData: nil,
                            hasDataForSelectedWeekEntries: true,
                            isEntryWeekLoading: false,
                            selectedYear: $selectedYear,
                            availableYears: Self.fakeAvailableYears,
                            yearData: Self.fakeYearData,
                            averageYearData: Self.fakeAvgYearData,
                            hasDataForSelectedYear: true,
                            isYearLoading: false,
                            hasInsufficientYearData: false,
                            entryYearData: Self.fakeEntryYearData,
                            averageEntryYearData: nil,
                            hasDataForSelectedYearEntries: true,
                            isEntryYearLoading: false,
                            onDaySelected: { _ in },
                            onWeekSelected: { _ in },
                            onYearSelected: { _ in },
                            onDownloadDay: {},
                            onDownloadWeek: {},
                            onDownloadYear: {},
                            getCurrentDate: { "2026-02-04" },
                            getCurrentYear: { "2026" },
                            formattedDateLong: { $0 },
                            findMostRecentDataTime: { data in
                                data.filter { $0.value > 0 }.keys.compactMap { Int($0) }.max().map { String($0) }
                            }
                        )
                    }
                } else {
                    InsightsView(
                        selectedPeriod: $selectedInsightsPeriod,
                        dayData: Self.fakeDayData,
                        averageDayData: Self.fakeAvgDayData,
                        weekData: Self.fakeWeekData,
                        averageWeekData: Self.fakeAvgWeekData,
                        yearData: Self.fakeYearData,
                        averageYearData: Self.fakeAvgYearData,
                        entryDayData: Self.fakeEntryDayData,
                        entryWeekData: Self.fakeEntryWeekData,
                        entryYearData: Self.fakeEntryYearData,
                        isDayLoading: false,
                        isWeekLoading: false,
                        isYearLoading: false
                    )
                }
            }
            .navigationBarTitle("Count Analytics", displayMode: .inline)
        }
        .preferredColorScheme(.dark)
        .environmentObject(AppSettings())
    }
}

#Preview("Historic View") {
    HistoricViewPreview()
}
