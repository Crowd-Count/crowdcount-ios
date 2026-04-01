import SwiftUI
import UIKit

/// Location-level history view — shows aggregated analytics for all devices in a location.
/// Uses server-side location endpoints (one API call per data type) instead of per-device aggregation.
struct LocationHistoricView: View {
    let location: AppLocation
    let devices: [Device]
    var initialTab: HistoricViewTab = .historicCounts

    @State private var selectedTab: HistoricViewTab = .historicCounts
    @State private var selectedInsightsPeriod: InsightsPeriod = .day
    @State private var selectedGraphDataType: GraphDataType = .entries
    @State private var selectedDay: String = "Today"
    @State private var selectedDayRaw: String = ""
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
    @State private var insightsDwellTimeMinutes: Double?
    @State private var insightsWeekDwellTime: [String: Double]? = nil
    @State private var insightsYearDwellTime: [String: Double]? = nil
    // Temporary: holds the last bundle's dwell time (NOT directly used by insights)
    @State private var _lastBundleDwellTime: Double? = nil
    @State private var insightsInitialLoadComplete: Bool = false
    // Insights-specific date selections (independent from History tab)
    @State private var insightsSelectedDay: String = "Today"
    @State private var insightsSelectedDayRaw: String = ""
    @State private var insightsSelectedWeek: WeekInfo? = nil
    @State private var insightsSelectedYear: String = "This Year"
    @State private var isInsightsDayLoading: Bool = false
    @State private var isInsightsWeekLoading: Bool = false
    @State private var isInsightsYearLoading: Bool = false
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

    // POS data
    @State private var posInsights: POSInsightsResponse?
    @State private var hasPOS: Bool = false
    @State private var showPOSConnectFromInsights: Bool = false
    @AppStorage("crowdcount_showPOSOverlay") private var showPOSOverlay: Bool = true
    @State private var posDayTransactions: [String: POSTransactionData.POSHourlyEntry]?
    @State private var posWeekTransactions: [String: Int]?
    @State private var posYearTransactions: [String: Int]?

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
                    .padding(.bottom, 4)

                    Text(selectedGraphDataType == .entries
                         ? "Total number of people who entered during each period."
                         : "Number of people present at each point in time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

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
                        entryYearData: entryYearData,
                        averageEntryYearData: averageEntryYearData,
                        hasDataForSelectedYearEntries: hasDataForSelectedYearEntries,
                        isEntryYearLoading: isEntryYearLoading,
                        posDayData: posDayTransactions,
                        posWeekData: posWeekTransactions,
                        posYearData: posYearTransactions,
                        hasPOS: hasPOS,
                        onDaySelected: { date in
                            let displayDate = (date == getCurrentDate()) ? "Today" : formattedDateLong(from: date)
                            selectedDay = displayDate
                            selectedDayRaw = date
                            Task {
                                await fetchDataViaBundle(
                                    dayDate: date,
                                    weekStartDate: selectedWeek?.startDate ?? getCurrentWeekStartDate(),
                                    year: selectedYear == "This Year" ? getCurrentYearInt() : Int(selectedYear) ?? getCurrentYearInt()
                                )
                                if date == getCurrentDate() { await fetchConnectionStatusAsync() }
                                // Fetch POS day transactions for the selected date
                                if hasPOS, let signing = signingDevice {
                                    await fetchPOSDayTransactions(date: date, signing: signing)
                                }
                            }
                        },
                        onWeekSelected: { week in
                            selectedWeek = week
                            Task {
                                await fetchDataViaBundle(
                                    dayDate: selectedDayRaw.isEmpty ? getCurrentDate() : selectedDayRaw,
                                    weekStartDate: week.startDate,
                                    year: selectedYear == "This Year" ? getCurrentYearInt() : Int(selectedYear) ?? getCurrentYearInt()
                                )
                                // Fetch POS week transactions for the selected week
                                if hasPOS, let signing = signingDevice {
                                    await fetchPOSWeekTransactions(weekStart: week.startDate, signing: signing)
                                }
                            }
                        },
                        onYearSelected: { year in
                            let displayYear = (year == getCurrentYear()) ? "This Year" : year
                            selectedYear = displayYear
                            let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                            Task {
                                await fetchDataViaBundle(
                                    dayDate: selectedDayRaw.isEmpty ? getCurrentDate() : selectedDayRaw,
                                    weekStartDate: selectedWeek?.startDate ?? getCurrentWeekStartDate(),
                                    year: yearInt
                                )
                                // Fetch POS year transactions for the selected year
                                if hasPOS, let signing = signingDevice {
                                    await fetchPOSYearTransactions(year: yearInt, signing: signing)
                                }
                            }
                        },
                        onDownloadDay: { Task { await downloadDayDataAsCSV() } },
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
                    dwellTimeMinutes: insightsDwellTimeMinutes,
                    dwellTimeWeekData: insightsWeekDwellTime,
                    dwellTimeYearData: insightsYearDwellTime,
                    availableDates: availableDates,
                    availableWeeks: availableWeeks,
                    availableYears: availableYears,
                    selectedDay: insightsSelectedDay,
                    selectedWeek: insightsSelectedWeek,
                    selectedYear: insightsSelectedYear,
                    onDaySelected: { date in
                        let displayDate = (date == getCurrentDate()) ? "Today" : formattedDateLong(from: date)
                        insightsSelectedDay = displayDate
                        insightsSelectedDayRaw = date
                        Task { await fetchInsightsDayData(date: date) }
                    },
                    onWeekSelected: { week in
                        insightsSelectedWeek = week
                        Task { await fetchInsightsWeekData(weekDate: week.startDate) }
                    },
                    onYearSelected: { year in
                        let displayYear = (year == getCurrentYear()) ? "This Year" : year
                        insightsSelectedYear = displayYear
                        let yearInt = (year == getCurrentYear()) ? getCurrentYearInt() : Int(year) ?? getCurrentYearInt()
                        Task { await fetchInsightsYearData(year: yearInt) }
                    },
                    getCurrentDate: getCurrentDate,
                    getCurrentYear: getCurrentYear,
                    formattedDateLong: formattedDateLong,
                    isDayLoading: !insightsInitialLoadComplete || isInsightsDayLoading,
                    isWeekLoading: !insightsInitialLoadComplete || isInsightsWeekLoading,
                    isYearLoading: !insightsInitialLoadComplete || isInsightsYearLoading,
                    posInsights: posInsights,
                    hasPOS: hasPOS,
                    onConnectPOS: { showPOSConnectFromInsights = true }
                )
            }
        }
        .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
        .navigationBarTitle(selectedTab == .historicCounts ? "History" : "Insights", displayMode: .inline)
        .sheet(isPresented: $showPOSConnectFromInsights) {
            POSConnectView(
                locationId: location.id,
                locationName: location.name,
                credentials: credentials,
                signingDevice: signingDevice ?? ("", ""),
                onConnected: {
                    Task { await loadPOSData() }
                }
            )
        }
        .onAppear {
            selectedTab = initialTab
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

        // Only update insights day data if insights is still viewing today
        if insightsSelectedDay == "Today" {
            insightsTodayData = combinedDayData
            insightsTodayAverage = combinedAvgDayData.isEmpty ? nil : combinedAvgDayData
        }
    }

    // MARK: - Initial Load

    @MainActor
    private func loadInitialData() async {
        isLoading = true
        selectedDayRaw = getCurrentDate()

        // Check POS status early so the toggle appears immediately
        if let signing = signingDevice {
            // Use cached status first for instant UI, then refresh in background
            if let cached = POSStatusManager.shared.getStatus(for: location.id) {
                hasPOS = cached.connected
            }
            Task {
                await POSStatusManager.shared.refreshStatus(for: location.id, credentials: credentials, signingDevice: signing)
                hasPOS = POSStatusManager.shared.isConnected(for: location.id)
            }
        }

        let todayDate = getCurrentDate()
        let weekStart = getCurrentWeekStartDate()
        let year = getCurrentYearInt()

        // Check prefetch cache for instant load
        let cache = HistoryPrefetchCache.shared
        if let cachedBundle = cache.get(locationId: location.id) {
            // Use cached available dates if present
            if let cachedDates = cache.getDates(locationId: location.id) {
                let localDates = TZHelper.utcDatesToLocalDates(cachedDates)
                self.availableDates = localDates.sorted(by: >)
                self.availableYears = Array(Set(localDates.map { formattedYear(from: $0) })).sorted(by: >)
                self.availableWeeks = generateAvailableWeeks(from: localDates)
                if let firstWeek = self.availableWeeks.first {
                    self.selectedWeek = firstWeek
                }
            } else {
                await fetchAvailableDatesAsync()
            }

            // Apply cached bundle instantly (no network call)
            applyBundleResponse(cachedBundle, dayDate: todayDate, weekStartDate: weekStart)

            // Consume the cache entry
            cache.remove(locationId: location.id)
        } else {
            // No cache — fetch normally
            await fetchAvailableDatesAsync()
            await fetchDataViaBundle(
                dayDate: todayDate,
                weekStartDate: weekStart,
                year: year
            )
        }

        await fetchConnectionStatusAsync()

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

        // Initialize insights date selections
        insightsSelectedDayRaw = todayDate
        if let firstWeek = self.availableWeeks.first {
            insightsSelectedWeek = firstWeek
        }

        // Day dwell time was saved by applyBundleResponse to _lastBundleDwellTime
        insightsDwellTimeMinutes = _lastBundleDwellTime

        // Fetch week & year dwell time (parallel, each with catch)
        if let signing = signingDevice {
            async let weekDwellTask = apiService.fetchLocationDwellTimeWeek(
                locationId: location.id, date: weekStart, credentials: credentials, signingDevice: signing
            )
            async let yearDwellTask = apiService.fetchLocationDwellTimeYear(
                locationId: location.id, year: year, credentials: credentials, signingDevice: signing
            )
            insightsWeekDwellTime = try? await weekDwellTask
            insightsYearDwellTime = try? await yearDwellTask
        }

        // Fetch POS data (non-blocking — POS is optional)
        await loadPOSData()

        insightsInitialLoadComplete = true
        isLoading = false
    }

    // MARK: - POS Data

    private func loadPOSData() async {
        // Fetch fresh POS connection status from server
        guard let signing = signingDevice else { return }
        await POSStatusManager.shared.refreshStatus(
            for: location.id,
            credentials: credentials,
            signingDevice: signing
        )
        hasPOS = POSStatusManager.shared.isConnected(for: location.id)

        guard hasPOS else { return }

        let todayStr = TZHelper.yyyyMMddLocal(from: Date())
        let weekStart = getCurrentWeekStartDate()
        let yearInt = getCurrentYearInt()

        // Fetch insights + day + week + year transactions in parallel
        async let insightsTask: Void = {
            do {
                let insights = try await self.apiService.fetchPOSInsights(
                    locationId: self.location.id,
                    credentials: self.credentials,
                    signingDevice: signing
                )
                await MainActor.run { self.posInsights = insights }
            } catch { }
        }()

        async let dayTxTask: Void = {
            do {
                let txData = try await self.apiService.fetchPOSTransactions(
                    locationId: self.location.id,
                    startDate: todayStr,
                    endDate: todayStr,
                    credentials: self.credentials,
                    signingDevice: signing
                )
                print("[POS] Day transactions loaded: \(txData.hourlyBreakdown.count) hours, total: \(txData.totalTransactions)")
                await MainActor.run { self.posDayTransactions = txData.hourlyBreakdown }
            } catch {
                print("[POS] Day transactions failed: \(error)")
            }
        }()

        async let weekTxTask: Void = {
            await self.fetchPOSWeekTransactions(weekStart: weekStart, signing: signing)
        }()

        async let yearTxTask: Void = {
            await self.fetchPOSYearTransactions(year: yearInt, signing: signing)
        }()

        _ = await (insightsTask, dayTxTask, weekTxTask, yearTxTask)
    }

    private func fetchPOSDayTransactions(date: String, signing: (String, String)) async {
        do {
            let txData = try await apiService.fetchPOSTransactions(
                locationId: location.id,
                startDate: date,
                endDate: date,
                credentials: credentials,
                signingDevice: signing
            )
            print("[POS] Day transactions loaded: \(txData.hourlyBreakdown.count) hours, total: \(txData.totalTransactions)")
            await MainActor.run { posDayTransactions = txData.hourlyBreakdown }
        } catch {
            print("[POS] Day transactions failed: \(error)")
            await MainActor.run { posDayTransactions = nil }
        }
    }

    private func fetchPOSWeekTransactions(weekStart: String, signing: (String, String)) async {
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var weekSales: [String: Int] = [:]

        // Fetch each day individually to get per-day transaction counts
        guard let startDate = TZHelper.localDate(from: weekStart) else { return }

        await withTaskGroup(of: (String, Int).self) { group in
            for i in 0..<7 {
                guard let dayDate = Calendar.current.date(byAdding: .day, value: i, to: startDate) else { continue }
                let dateStr = TZHelper.yyyyMMddLocal(from: dayDate)
                let dayName = dayNames[i]

                group.addTask {
                    do {
                        let txData = try await self.apiService.fetchPOSTransactions(
                            locationId: self.location.id,
                            startDate: dateStr,
                            endDate: dateStr,
                            credentials: self.credentials,
                            signingDevice: signing
                        )
                        return (dayName, txData.totalTransactions)
                    } catch {
                        return (dayName, 0)
                    }
                }
            }

            for await (dayName, count) in group {
                weekSales[dayName] = count
            }
        }

        print("[POS] Week transactions loaded: \(weekSales)")
        await MainActor.run { posWeekTransactions = weekSales }
    }

    private func fetchPOSYearTransactions(year: Int, signing: (String, String)) async {
        let monthNames = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]
        var yearSales: [String: Int] = [:]

        await withTaskGroup(of: (String, Int).self) { group in
            for i in 0..<12 {
                let monthNum = String(format: "%02d", i + 1)
                let startDate = "\(year)-\(monthNum)-01"
                let lastDay = Calendar.current.range(of: .day, in: .month,
                    for: Calendar.current.date(from: DateComponents(year: year, month: i + 1))!)!.count
                let endDate = "\(year)-\(monthNum)-\(String(format: "%02d", lastDay))"
                let monthName = monthNames[i]

                group.addTask {
                    do {
                        let txData = try await self.apiService.fetchPOSTransactions(
                            locationId: self.location.id,
                            startDate: startDate,
                            endDate: endDate,
                            credentials: self.credentials,
                            signingDevice: signing
                        )
                        return (monthName, txData.totalTransactions)
                    } catch {
                        return (monthName, 0)
                    }
                }
            }

            for await (monthName, count) in group {
                yearSales[monthName] = count
            }
        }

        await MainActor.run { posYearTransactions = yearSales }
    }

    /// Apply a pre-fetched bundle response to all chart state variables.
    /// Used by both `fetchDataViaBundle` (after network call) and `loadInitialData` (from prefetch cache).
    @MainActor
    private func applyBundleResponse(_ bundle: APIService.InsightsBundleResponse, dayDate: String, weekStartDate: String) {
        let utcDates = TZHelper.utcDatesForLocalDay(dayDate)

        // --- Count day data (timezone shift) ---
        var combinedDayData: [String: Double] = [:]
        var combinedAvgDayData: [String: Double] = [:]
        let localBins1 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDates.primary, bins: bundle.dayView, targetLocalDate: dayDate)
        for (hour, value) in localBins1 { combinedDayData[hour, default: 0] += value }
        let avgLocalBins1 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDates.primary, bins: bundle.averageDayView, targetLocalDate: dayDate)
        for (hour, value) in avgLocalBins1 { combinedAvgDayData[hour, default: 0] += value }

        if let sec = utcDates.secondary {
            if let dv2 = bundle.dayView2 {
                let localBins2 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: sec, bins: dv2, targetLocalDate: dayDate)
                for (hour, value) in localBins2 { combinedDayData[hour, default: 0] += value }
            }
            if let adv2 = bundle.averageDayView2 {
                let avgLocalBins2 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: sec, bins: adv2, targetLocalDate: dayDate)
                for (hour, value) in avgLocalBins2 { combinedAvgDayData[hour, default: 0] += value }
            }
        }

        hasDataForSelectedDay = !combinedDayData.isEmpty
        dayData = combinedDayData
        averageDayData = combinedAvgDayData.isEmpty ? nil : combinedAvgDayData
        mostRecentDataTime = findMostRecentDataTime(in: combinedDayData)

        // --- Entry day data (timezone shift) ---
        var combinedEntryDayData: [String: Double] = [:]
        var combinedAvgEntryDayData: [String: Double] = [:]
        let entryLocalBins1 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDates.primary, bins: bundle.entryDayView, targetLocalDate: dayDate)
        for (hour, value) in entryLocalBins1 { combinedEntryDayData[hour, default: 0] += value }
        let avgEntryLocalBins1 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDates.primary, bins: bundle.averageEntryDayView, targetLocalDate: dayDate)
        for (hour, value) in avgEntryLocalBins1 { combinedAvgEntryDayData[hour, default: 0] += value }

        if let sec = utcDates.secondary {
            if let edv2 = bundle.entryDayView2 {
                let entryLocalBins2 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: sec, bins: edv2, targetLocalDate: dayDate)
                for (hour, value) in entryLocalBins2 { combinedEntryDayData[hour, default: 0] += value }
            }
            if let aedv2 = bundle.averageEntryDayView2 {
                let avgEntryLocalBins2 = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: sec, bins: aedv2, targetLocalDate: dayDate)
                for (hour, value) in avgEntryLocalBins2 { combinedAvgEntryDayData[hour, default: 0] += value }
            }
        }

        hasDataForSelectedDayEntries = !combinedEntryDayData.isEmpty
        entryDayData = combinedEntryDayData
        averageEntryDayData = combinedAvgEntryDayData.isEmpty ? nil : combinedAvgEntryDayData

        // --- Week data (tz-correct from server + strip future days) ---
        let filteredWeek = adjustWeekDataForTimezone(from: bundle.weekView, weekStartDate: weekStartDate)
        hasDataForSelectedWeek = !filteredWeek.isEmpty
        weekData = filteredWeek
        mostRecentWeekDay = findMostRecentWeekDay(in: filteredWeek)
        let filteredAvgWeek = adjustWeekDataForTimezone(from: bundle.averageWeekView, weekStartDate: weekStartDate)
        averageWeekData = filteredAvgWeek.isEmpty ? nil : filteredAvgWeek

        let filteredEntryWeek = adjustWeekDataForTimezone(from: bundle.entryWeekView, weekStartDate: weekStartDate)
        hasDataForSelectedWeekEntries = !filteredEntryWeek.isEmpty
        entryWeekData = filteredEntryWeek
        let filteredAvgEntryWeek = adjustWeekDataForTimezone(from: bundle.averageEntryWeekView, weekStartDate: weekStartDate)
        averageEntryWeekData = filteredAvgEntryWeek.isEmpty ? nil : filteredAvgEntryWeek

        // --- Year data ---
        yearData = bundle.yearView
        hasDataForSelectedYear = !bundle.yearView.isEmpty
        averageYearData = bundle.averageYearView
        entryYearData = bundle.entryYearView
        hasDataForSelectedYearEntries = !bundle.entryYearView.isEmpty
        averageEntryYearData = bundle.averageEntryYearView

        // Save dwell time to temporary var (NOT to insightsDwellTimeMinutes — that's only set in loadInitialData / insights fetchers)
        _lastBundleDwellTime = bundle.dwellTimeMinutes
    }

    /// Fetch all chart data via a single insights bundle call.
    /// Falls back to individual calls if the bundle endpoint is unavailable.
    @MainActor
    private func fetchDataViaBundle(dayDate: String, weekStartDate: String, year: Int) async {
        isDayLoading = true
        isWeekLoading = true
        isYearLoading = true
        isEntryDayLoading = true
        isEntryWeekLoading = true
        isEntryYearLoading = true

        guard let signing = signingDevice else {
            isDayLoading = false; isWeekLoading = false; isYearLoading = false
            isEntryDayLoading = false; isEntryWeekLoading = false; isEntryYearLoading = false
            return
        }

        let utcDates = TZHelper.utcDatesForLocalDay(dayDate)

        do {
            let bundle = try await apiService.fetchLocationInsightsBundle(
                locationId: location.id,
                date: utcDates.primary,
                date2: utcDates.secondary,
                weekDate: weekStartDate,
                year: year,
                credentials: credentials,
                signingDevice: signing
            )

            applyBundleResponse(bundle, dayDate: dayDate, weekStartDate: weekStartDate)

            // Brief delay so charts render before loading overlay hides
            try? await Task.sleep(nanoseconds: 150_000_000)

        } catch {
            // Fallback to individual calls if bundle endpoint unavailable
            async let d1: () = fetchDayDataAsync(for: dayDate)
            async let d2: () = fetchWeekDataAsync(for: weekStartDate)
            async let d3: () = fetchYearDataAsync(for: year)
            async let d4: () = fetchEntryDayDataAsync(for: dayDate)
            async let d5: () = fetchEntryWeekDataAsync(for: weekStartDate)
            async let d6: () = fetchEntryYearDataAsync(for: year)
            _ = await (d1, d2, d3, d4, d5, d6)
            return
        }

        isDayLoading = false
        isWeekLoading = false
        isYearLoading = false
        isEntryDayLoading = false
        isEntryWeekLoading = false
        isEntryYearLoading = false
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
            let filtered = adjustWeekDataForTimezone(from: data, weekStartDate: formattedStartDate)
            hasDataForSelectedWeek = !filtered.isEmpty
            weekData = filtered
            mostRecentWeekDay = findMostRecentWeekDay(in: filtered)
        } catch {
            print("Error fetching location week data: \(error)")
            hasDataForSelectedWeek = false
        }

        do {
            let avgData = try await apiService.fetchLocationAverageWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            let filteredAvg = adjustWeekDataForTimezone(from: avgData, weekStartDate: formattedStartDate)
            averageWeekData = filteredAvg.isEmpty ? nil : filteredAvg
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
        } catch {
            print("Error fetching location year data: \(error)")
            self.hasDataForSelectedYear = false
            self.averageYearData = nil
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
            let filtered = adjustWeekDataForTimezone(from: data, weekStartDate: formattedStartDate)
            hasDataForSelectedWeekEntries = !filtered.isEmpty
            entryWeekData = filtered
        } catch {
            print("Error fetching location entry week data: \(error)")
            hasDataForSelectedWeekEntries = false
        }

        do {
            let avgData = try await apiService.fetchLocationAverageEntryWeekData(
                locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
            )
            let filteredAvg = adjustWeekDataForTimezone(from: avgData, weekStartDate: formattedStartDate)
            averageEntryWeekData = filteredAvg.isEmpty ? nil : filteredAvg
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

        guard let signing = signingDevice else { return }

        do {
            let dates = try await apiService.fetchLocationAvailableDates(
                locationId: location.id,
                credentials: credentials,
                signingDevice: signing
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
            guard let device = devices.first(where: { $0.deviceId == deviceId }) else { continue }
            if let status = try? await apiService.checkConnectionStatus(deviceId: deviceId, password: device.password),
               status == "online" {
                anyOnline = true
                break
            }
        }
        isDeviceOnline = anyOnline
    }

    // MARK: - Insights Data Fetchers (independent from History tab)

    @MainActor
    private func fetchInsightsDayData(date: String) async {
        isInsightsDayLoading = true
        defer { isInsightsDayLoading = false }

        guard let signing = signingDevice else { return }

        let localDate = date
        let utcDates = TZHelper.utcDatesForLocalDay(localDate)
        let utcDatesList = [utcDates.primary] + (utcDates.secondary.map { [$0] } ?? [])

        // Fetch day data + average + entry data + average entry data (all with individual catch)
        var combinedDayData: [String: Double] = [:]
        var combinedAvgDayData: [String: Double] = [:]
        var combinedEntryDayData: [String: Double] = [:]
        var combinedAvgEntryDayData: [String: Double] = [:]

        for utcDate in utcDatesList {
            if let data = try? await apiService.fetchLocationDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: data, targetLocalDate: localDate)
                for (hour, value) in localBins { combinedDayData[hour, default: 0] += value }
            }
            if let avgData = try? await apiService.fetchLocationAverageDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgData, targetLocalDate: localDate)
                for (hour, value) in localBins { combinedAvgDayData[hour, default: 0] += value }
            }
            if let entryData = try? await apiService.fetchLocationEntryDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: entryData, targetLocalDate: localDate)
                for (hour, value) in localBins { combinedEntryDayData[hour, default: 0] += value }
            }
            if let avgEntryData = try? await apiService.fetchLocationAverageEntryDayData(
                locationId: location.id, date: utcDate, credentials: credentials, signingDevice: signing
            ) {
                let localBins = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgEntryData, targetLocalDate: localDate)
                for (hour, value) in localBins { combinedAvgEntryDayData[hour, default: 0] += value }
            }
        }

        insightsTodayData = combinedDayData
        insightsTodayAverage = combinedAvgDayData.isEmpty ? nil : combinedAvgDayData
        insightsEntryTodayData = combinedEntryDayData
        insightsAvgEntryTodayData = combinedAvgEntryDayData.isEmpty ? nil : combinedAvgEntryDayData

        // Fetch dwell time for this day via bundle endpoint (it returns dwell_time_view for the given date)
        let weekStart = insightsSelectedWeek?.startDate ?? getCurrentWeekStartDate()
        let yearInt = insightsSelectedYear == "This Year" ? getCurrentYearInt() : Int(insightsSelectedYear) ?? getCurrentYearInt()
        if let bundle = try? await apiService.fetchLocationInsightsBundle(
            locationId: location.id,
            date: utcDates.primary,
            date2: utcDates.secondary,
            weekDate: weekStart,
            year: yearInt,
            credentials: credentials,
            signingDevice: signing
        ) {
            insightsDwellTimeMinutes = bundle.dwellTimeMinutes
        }
    }

    @MainActor
    private func fetchInsightsWeekData(weekDate: String) async {
        isInsightsWeekLoading = true
        defer { isInsightsWeekLoading = false }

        guard let signing = signingDevice else { return }

        let formattedStartDate = weekDate.isEmpty ? getCurrentWeekStartDate() : weekDate

        // Fetch all 4 week data types + dwell time (each with individual catch)
        let weekResult = try? await apiService.fetchLocationWeekData(
            locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
        )
        let avgWeekResult = try? await apiService.fetchLocationAverageWeekData(
            locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
        )
        let entryWeekResult = try? await apiService.fetchLocationEntryWeekData(
            locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
        )
        let avgEntryWeekResult = try? await apiService.fetchLocationAverageEntryWeekData(
            locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
        )
        let dwellWeekResult = try? await apiService.fetchLocationDwellTimeWeek(
            locationId: location.id, date: formattedStartDate, credentials: credentials, signingDevice: signing
        )

        // Strip future days for current week
        insightsThisWeekData = adjustWeekDataForTimezone(from: weekResult ?? [:], weekStartDate: formattedStartDate)
        insightsThisWeekAverage = {
            let filtered = adjustWeekDataForTimezone(from: avgWeekResult ?? [:], weekStartDate: formattedStartDate)
            return filtered.isEmpty ? nil : filtered
        }()
        insightsEntryThisWeekData = adjustWeekDataForTimezone(from: entryWeekResult ?? [:], weekStartDate: formattedStartDate)
        insightsAvgEntryThisWeekData = {
            let filtered = adjustWeekDataForTimezone(from: avgEntryWeekResult ?? [:], weekStartDate: formattedStartDate)
            return filtered.isEmpty ? nil : filtered
        }()

        insightsWeekDwellTime = dwellWeekResult
    }

    @MainActor
    private func fetchInsightsYearData(year: Int) async {
        isInsightsYearLoading = true
        defer { isInsightsYearLoading = false }

        guard let signing = signingDevice else { return }

        // Fetch all 4 year data types + dwell time (each with individual catch)
        let yearResult = try? await apiService.fetchLocationYearData(
            locationId: location.id, year: year, credentials: credentials, signingDevice: signing
        )
        let avgYearResult = try? await apiService.fetchLocationAverageYearData(
            locationId: location.id, year: year, credentials: credentials, signingDevice: signing
        )
        let entryYearResult = try? await apiService.fetchLocationEntryYearData(
            locationId: location.id, year: year, credentials: credentials, signingDevice: signing
        )
        let avgEntryYearResult = try? await apiService.fetchLocationAverageEntryYearData(
            locationId: location.id, year: year, credentials: credentials, signingDevice: signing
        )
        let dwellYearResult = try? await apiService.fetchLocationDwellTimeYear(
            locationId: location.id, year: year, credentials: credentials, signingDevice: signing
        )

        insightsThisYearData = yearResult ?? [:]
        insightsThisYearAverage = avgYearResult
        insightsEntryThisYearData = entryYearResult ?? [:]
        insightsAvgEntryThisYearData = avgEntryYearResult
        insightsYearDwellTime = dwellYearResult
    }

    // MARK: - CSV Downloads

    @MainActor
    private func downloadDayDataAsCSV() async {
        guard let signing = signingDevice else { return }

        let dataType = selectedGraphDataType == .entries ? "entries" : "count"
        let localDate = selectedDay == "Today" ? getCurrentDate() : formattedDateShort(from: selectedDay)

        // Fetch 15-minute interval data from server
        do {
            let response = try await apiService.fetchLocationDayDataDetailed(
                locationId: location.id,
                date: localDate,
                dataType: dataType,
                credentials: credentials,
                signingDevice: signing
            )

            guard !response.data.isEmpty else { return }

            // Build CSV with all 96 quarter-hour slots
            var csvContent = "Time,\(dataType == "entries" ? "Entries" : "Count"),Average\n"
            for slot in 0..<96 {
                let hour = slot / 4
                let minute = (slot % 4) * 15
                let label = "\(hour):\(String(format: "%02d", minute))"
                if let value = response.data[label] {
                    let avg = response.average[label]
                    let avgString = avg != nil ? String(format: "%.1f", avg!) : ""
                    csvContent += "\(label),\(String(format: "%.1f", value)),\(avgString)\n"
                }
            }

            guard let csvData = csvContent.data(using: .utf8) else { return }

            let fileName = "location_\(location.name)_day_\(localDate).csv"
            if let topController = UIApplication.shared.topViewController() {
                presentShareSheet(data: csvData, fileName: fileName, from: topController)
            }
        } catch {
            // Fallback to hourly data if detailed endpoint not available
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

    /// For the current week: strip future days.
    /// The server already handles timezone-correct aggregation via tz_offset_minutes,
    /// so we only need to remove days that haven't happened yet in the local week.
    func adjustWeekDataForTimezone(from data: [String: Double], weekStartDate: String) -> [String: Double] {
        let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let isCurrentWeek = weekStartDate == getCurrentWeekStartDate()

        guard isCurrentWeek else { return data }

        // weekday: 1=Sunday, 2=Monday, ... 7=Saturday → convert to 0-based Monday index
        let weekday = Calendar.current.component(.weekday, from: Date())
        let todayIndex = (weekday - 2 + 7) % 7 // 0=Monday ... 6=Sunday

        var filtered = data
        // Strip future days
        for i in (todayIndex + 1)..<dayOrder.count {
            filtered.removeValue(forKey: dayOrder[i])
        }
        return filtered
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
