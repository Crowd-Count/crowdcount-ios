import SwiftUI
import UIKit

/// Location-level history view — shows aggregated analytics for all devices in a location.
/// Uses server-side location endpoints (one API call per data type) instead of per-device aggregation.
struct LocationHistoricView: View {
    let location: AppLocation
    let devices: [Device]

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

    private let apiService = APIService.shared

    /// Credentials for all devices in this location
    private var credentials: [[String: String]] {
        devices.filter { location.deviceIds.contains($0.deviceId) }
            .map { ["device_id": $0.deviceId, "password": $0.password] }
    }

    /// First device used for HMAC signing
    private var signingDevice: (String, String)? {
        guard let first = devices.first(where: { location.deviceIds.contains($0.deviceId) }) else { return nil }
        return (first.deviceId, first.password)
    }

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
                    // Data type picker (Population vs Entries)
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
                            let displayDate = (date == getCurrentDate()) ? "Today" : formattedDateLong(from: date)
                            selectedDay = displayDate
                            Task { await fetchDayDataAsync(for: date) }
                            if selectedGraphDataType == .entries {
                                Task { await fetchEntryDayDataAsync(for: date) }
                            }
                            if date == getCurrentDate() {
                                Task { await fetchConnectionStatusAsync() }
                            }
                        },
                        onWeekSelected: { week in
                            selectedWeek = week
                            Task { await fetchWeekDataAsync(for: week.startDate) }
                            if selectedGraphDataType == .entries {
                                Task { await fetchEntryWeekDataAsync(for: week.startDate) }
                            }
                        },
                        onYearSelected: { year in
                            let displayYear = (year == getCurrentYear()) ? "This Year" : year
                            selectedYear = displayYear
                            let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                            Task { await fetchYearDataAsync(for: yearInt) }
                            if selectedGraphDataType == .entries {
                                Task { await fetchEntryYearDataAsync(for: yearInt) }
                            }
                        },
                        onDownloadDay: { downloadDayDataAsCSV() },
                        onDownloadWeek: { downloadWeekDataAsCSV() },
                        onDownloadYear: { downloadYearDataAsCSV() },
                        getCurrentDate: getCurrentDate,
                        getCurrentYear: getCurrentYear,
                        formattedDateLong: formattedDateLong,
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
            Task { await loadInitialData() }
            startAutoRefreshTimer()
        }
        .onDisappear {
            stopAutoRefreshTimer()
        }
        .onChange(of: selectedDay) { _, newValue in
            if newValue == "Today" {
                startAutoRefreshTimer()
            } else {
                stopAutoRefreshTimer()
            }
        }
    }

    // MARK: - Auto-Refresh Timer

    private func startAutoRefreshTimer() {
        guard selectedDay == "Today" else { return }
        stopAutoRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in await refreshTodayData() }
        }
    }

    private func stopAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @MainActor
    private func refreshTodayData() async {
        guard let signing = signingDevice else { return }

        // Refresh connection status for first device
        await fetchConnectionStatusAsync()

        // Silently fetch fresh today data
        let localDate = getCurrentDate()
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesList = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        // Fetch day data from both UTC dates and merge with timezone shift
        var combinedDayData: [String: Double] = [:]
        var combinedAvgDayData: [String: Double] = [:]

        for utcDate in utcDatesList {
            if let data = try? await apiService.fetchLocationDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: data, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedDayData[hour, default: 0] += value
                }
            }
            if let avgData = try? await apiService.fetchLocationAverageDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgData, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedAvgDayData[hour, default: 0] += value
                }
            }
        }

        if selectedDay == "Today" {
            dayData = combinedDayData
            averageDayData = combinedAvgDayData.isEmpty ? nil : combinedAvgDayData
            mostRecentDataTime = findMostRecentDataTime(in: combinedDayData)
        }

        insightsTodayData = combinedDayData
        insightsTodayAverage = combinedAvgDayData.isEmpty ? nil : combinedAvgDayData
    }

    // MARK: - Initial Load

    @MainActor
    private func loadInitialData() async {
        isLoading = true
        isDayLoading = true
        isWeekLoading = true
        isYearLoading = true

        await fetchAvailableDatesAsync()

        async let dayTask: () = fetchDayDataAsync(for: getCurrentDate())
        async let weekTask: () = fetchWeekDataAsync(for: getCurrentWeekStartDate())
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

    // MARK: - Day Data

    @MainActor
    private func fetchDayDataAsync(for date: String) async {
        isDayLoading = true
        defer { isDayLoading = false }

        guard let signing = signingDevice else { return }

        let localDate = (date == "Today") ? getCurrentDate() : date
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesList = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        var combinedData: [String: Double] = [:]
        var combinedAvgData: [String: Double] = [:]

        for utcDate in utcDatesList {
            if let data = try? await apiService.fetchLocationDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: data, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedData[hour, default: 0] += value
                }
            }
            if let avgData = try? await apiService.fetchLocationAverageDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgData, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedAvgData[hour, default: 0] += value
                }
            }
        }

        hasDataForSelectedDay = !combinedData.isEmpty
        dayData = combinedData
        averageDayData = combinedAvgData.isEmpty ? nil : combinedAvgData
        mostRecentDataTime = findMostRecentDataTime(in: combinedData)
    }

    // MARK: - Week Data

    @MainActor
    private func fetchWeekDataAsync(for startDate: String) async {
        isWeekLoading = true
        defer { isWeekLoading = false }

        guard let signing = signingDevice else { return }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = startDate
        }

        do {
            let data = try await apiService.fetchLocationWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            hasDataForSelectedWeek = !data.isEmpty
            weekData = data
            mostRecentWeekDay = findMostRecentWeekDay(in: data)
        } catch {
            print("Error fetching location week data: \(error)")
            hasDataForSelectedWeek = false
        }

        do {
            let avgData = try await apiService.fetchLocationAverageWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            averageWeekData = avgData.isEmpty ? nil : avgData
        } catch {
            print("Error fetching location average week data: \(error)")
            averageWeekData = nil
        }
    }

    // MARK: - Year Data

    @MainActor
    private func fetchYearDataAsync(for year: Int) async {
        isYearLoading = true
        defer { isYearLoading = false }

        guard let signing = signingDevice else { return }

        do {
            async let yearTask = apiService.fetchLocationYearData(
                locationId: location.id, year: year, credentials: credentials, signingDevice: signing
            )
            async let avgTask = apiService.fetchLocationAverageYearData(
                locationId: location.id, year: year, credentials: credentials, signingDevice: signing
            )

            let yearDataResult = try await yearTask
            let avgDataResult = try? await avgTask

            self.yearData = yearDataResult
            self.hasDataForSelectedYear = !yearDataResult.isEmpty
            self.averageYearData = avgDataResult
            self.hasInsufficientYearData = avgDataResult == nil
        } catch {
            print("Error fetching location year data: \(error)")
            self.hasDataForSelectedYear = false
            self.averageYearData = nil
            self.hasInsufficientYearData = true
        }
    }

    // MARK: - Entry Data

    @MainActor
    private func fetchEntryDataForCurrentSelections() async {
        let dayDate = selectedDay == "Today" ? getCurrentDate() : formattedDateShort(from: selectedDay)
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

        guard let signing = signingDevice else { return }

        let localDate = (date == getCurrentDate()) ? getCurrentDate() : date
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesList = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        var combinedData: [String: Double] = [:]
        var combinedAvgData: [String: Double] = [:]

        for utcDate in utcDatesList {
            if let data = try? await apiService.fetchLocationEntryDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: data, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedData[hour, default: 0] += value
                }
            }
            if let avgData = try? await apiService.fetchLocationAverageEntryDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgData, targetLocalDate: localDate)
                for (hour, value) in localBins {
                    combinedAvgData[hour, default: 0] += value
                }
            }
        }

        hasDataForSelectedDayEntries = !combinedData.isEmpty
        entryDayData = combinedData
        averageEntryDayData = combinedAvgData.isEmpty ? nil : combinedAvgData
    }

    @MainActor
    private func fetchEntryWeekDataAsync(for startDate: String) async {
        isEntryWeekLoading = true
        defer { isEntryWeekLoading = false }

        guard let signing = signingDevice else { return }

        let formattedStartDate: String
        if startDate.isEmpty || startDate == "This Week" {
            formattedStartDate = getCurrentWeekStartDate()
        } else {
            formattedStartDate = startDate
        }

        do {
            let data = try await apiService.fetchLocationEntryWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            hasDataForSelectedWeekEntries = !data.isEmpty
            entryWeekData = data
        } catch {
            print("Error fetching location entry week data: \(error)")
            hasDataForSelectedWeekEntries = false
        }

        do {
            let avgData = try await apiService.fetchLocationAverageEntryWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            averageEntryWeekData = avgData.isEmpty ? nil : avgData
        } catch {
            averageEntryWeekData = nil
        }
    }

    @MainActor
    private func fetchEntryYearDataAsync(for year: Int) async {
        isEntryYearLoading = true
        defer { isEntryYearLoading = false }

        guard let signing = signingDevice else { return }

        do {
            let data = try await apiService.fetchLocationEntryYearData(
                locationId: location.id, year: year, credentials: credentials, signingDevice: signing
            )
            hasDataForSelectedYearEntries = !data.isEmpty
            entryYearData = data
        } catch {
            print("Error fetching location entry year data: \(error)")
            hasDataForSelectedYearEntries = false
        }

        do {
            let avgData = try await apiService.fetchLocationAverageEntryYearData(
                locationId: location.id, year: year, credentials: credentials, signingDevice: signing
            )
            averageEntryYearData = (avgData?.isEmpty ?? true) ? nil : avgData
        } catch {
            averageEntryYearData = nil
        }
    }

    // MARK: - Available Dates

    @MainActor
    private func fetchAvailableDatesAsync() async {
        guard signingDevice != nil else { return }

        do {
            let deviceCreds = devices
                .filter { location.deviceIds.contains($0.deviceId) }
                .map { (deviceId: $0.deviceId, password: $0.password) }
            let dates = try await apiService.fetchLocationAvailableDates(
                deviceCredentials: deviceCreds
            )

            let localDates = TZHelper.utcDatesToLocalDates(dates)
            self.availableDates = localDates.sorted(by: >)
            self.availableYears = Array(Set(localDates.map { formattedYear(from: $0) })).sorted(by: >)
            self.availableWeeks = generateAvailableWeeks(from: localDates)

            if let firstWeek = self.availableWeeks.first {
                self.selectedWeek = firstWeek
            }
        } catch {
            print("Error fetching location available dates: \(error)")
        }
    }

    // MARK: - Connection Status

    @MainActor
    private func fetchConnectionStatusAsync() async {
        // Check if any device in location is online
        var anyOnline = false
        for deviceId in location.deviceIds {
            if let status = try? await apiService.checkConnectionStatus(deviceId: deviceId),
               status == "online" {
                anyOnline = true
                break
            }
        }
        isDeviceOnline = anyOnline
    }

    // MARK: - CSV Downloads

    private func downloadDayDataAsCSV() {
        let dataToExport = selectedGraphDataType == .entries ? entryDayData : dayData
        let avgToExport = selectedGraphDataType == .entries ? averageEntryDayData : averageDayData
        guard !dataToExport.isEmpty else { return }

        let hourOrder = (0...23).map { String($0) }

        var csvContent = "Hour,Count,Average\n"
        for hour in hourOrder {
            if let count = dataToExport[hour] {
                let average = avgToExport?[hour]
                let averageString = average != nil ? String(format: "%.1f", average!) : ""
                csvContent += "\(hour):00,\(String(format: "%.1f", count)),\(averageString)\n"
            }
        }

        guard let csvData = csvContent.data(using: .utf8) else { return }

        let dateLabel = selectedDay == "Today" ? getCurrentDate() : formattedDateShort(from: selectedDay)
        let fileName = "location_\(location.name)_day_\(dateLabel).csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    private func downloadWeekDataAsCSV() {
        let dataToExport = selectedGraphDataType == .entries ? entryWeekData : weekData
        let avgToExport = selectedGraphDataType == .entries ? averageEntryWeekData : averageWeekData
        guard !dataToExport.isEmpty else { return }

        let weekdayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        var csvContent = "Day,Count,Average\n"
        for day in weekdayOrder {
            let count = dataToExport[day] ?? 0
            let average = avgToExport?[day]
            let averageString = average != nil ? String(format: "%.1f", average!) : ""
            csvContent += "\(day),\(String(format: "%.1f", count)),\(averageString)\n"
        }

        guard let csvData = csvContent.data(using: .utf8) else { return }

        let weekLabel = selectedWeek?.startDate ?? "unknown"
        let fileName = "location_\(location.name)_week_\(weekLabel).csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    private func downloadYearDataAsCSV() {
        let dataToExport = selectedGraphDataType == .entries ? entryYearData : yearData
        let avgToExport = selectedGraphDataType == .entries ? averageEntryYearData : averageYearData
        guard !dataToExport.isEmpty else { return }

        let monthOrder = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

        var csvContent = "Month,Count,Average\n"
        for month in monthOrder {
            if let count = dataToExport[month] {
                let average = avgToExport?[month]
                let averageString = average != nil ? String(format: "%.1f", average!) : ""
                csvContent += "\(month),\(String(format: "%.1f", count)),\(averageString)\n"
            }
        }

        guard let csvData = csvContent.data(using: .utf8) else { return }

        let yearValue = selectedYear == "This Year" ? getCurrentYear() : selectedYear
        let fileName = "location_\(location.name)_year_\(yearValue).csv"

        if let topController = UIApplication.shared.topViewController() {
            presentShareSheet(data: csvData, fileName: fileName, from: topController)
        }
    }

    // MARK: - Helpers

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
            if nonZeroEntries.keys.contains(day) { return day }
        }
        return nonZeroEntries.keys.first
    }

    func formattedDateLong(from date: String) -> String {
        guard let d = TZHelper.localDate(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = .current
        f.locale = .current
        f.dateStyle = .long
        return f.string(from: d)
    }

    func formattedDateShort(from longDate: String) -> String {
        let fIn = DateFormatter()
        fIn.timeZone = .current
        fIn.locale = .current
        fIn.dateStyle = .long
        guard let d = fIn.date(from: longDate) else { return longDate }
        return TZHelper.yyyyMMddLocal(from: d)
    }

    func formattedYear(from date: String) -> String {
        guard let d = TZHelper.localDate(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "yyyy"
        return f.string(from: d)
    }

    func getCurrentYear() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: Date())
    }

    func getCurrentYearInt() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    func getCurrentDate() -> String {
        TZHelper.yyyyMMddLocal(from: Date())
    }

    func getCurrentWeekStartDate() -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday — must match generateAvailableWeeks
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: startOfWeek)
    }

    func generateAvailableWeeks(from dates: [String]) -> [WeekInfo] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
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
        let f = DateFormatter()
        f.dateFormat = "MMM dd"
        let startOfWeek = f.string(from: date)
        let endOfWeek = f.string(from: Calendar.current.date(byAdding: .day, value: 6, to: date)!)
        return "\(startOfWeek) - \(endOfWeek)"
    }
}
