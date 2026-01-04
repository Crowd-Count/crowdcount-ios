import Foundation

// MARK: - Cache Entry
private struct CacheEntry<T> {
    let value: T
    let timestamp: Date
    let ttl: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

// MARK: - Request Deduplication
private actor InFlightRequests {
    private var requests: [String: Task<Data, Error>] = [:]

    func getOrCreate(key: String, operation: @escaping () async throws -> Data) async throws -> Data {
        if let existingTask = requests[key] {
            return try await existingTask.value
        }

        let task = Task<Data, Error> {
            try await operation()
        }

        requests[key] = task

        do {
            let result = try await task.value
            requests.removeValue(forKey: key)
            return result
        } catch {
            requests.removeValue(forKey: key)
            throw error
        }
    }

    func cancel(key: String) {
        if let task = requests[key] {
            task.cancel()
            requests.removeValue(forKey: key)
        }
    }

    func cancelPrefix(_ prefix: String) {
        for (key, task) in requests where key.hasPrefix(prefix) {
            task.cancel()
            requests.removeValue(forKey: key)
        }
    }
}

// MARK: - Cache Manager
actor CacheManager {
    static let shared = CacheManager()

    private var cache: [String: Any] = [:]

    // TTL constants (in seconds)
    enum TTL {
        static let serverStatus: TimeInterval = 2.0       // Checked every 3s, cache for 2s
        static let currentCount: TimeInterval = 0.5       // Short cache for live counts
        static let overcrowding: TimeInterval = 4.0       // Checked every 5s, cache for 4s
        static let connectionStatus: TimeInterval = 2.0   // Short cache
        static let availableDates: TimeInterval = 60.0    // Cache for 1 minute
        static let dayData: TimeInterval = 30.0           // Cache day data for 30s
        static let weekData: TimeInterval = 60.0          // Cache week data for 1 min
        static let yearData: TimeInterval = 120.0         // Cache year data for 2 min
        static let alertCheck: TimeInterval = 30.0        // Cache alert check for 30s
        static let locations: TimeInterval = 30.0         // Cache map locations for 30s
    }

    func get<T>(_ key: String) -> T? {
        guard let entry = cache[key] as? CacheEntry<T> else { return nil }
        if entry.isExpired {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func set<T>(_ key: String, value: T, ttl: TimeInterval) {
        cache[key] = CacheEntry(value: value, timestamp: Date(), ttl: ttl)
    }

    func invalidate(_ key: String) {
        cache.removeValue(forKey: key)
    }

    func invalidatePrefix(_ prefix: String) {
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    func clear() {
        cache.removeAll()
    }
}

// MARK: - API Service
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    private let inFlightRequests = InFlightRequests()
    private let cache = CacheManager.shared
    private let session: URLSession

    // Track last values for change detection
    private var lastServerStatus: Bool?
    private var lastCounts: [String: Int] = [:]
    private var lastOvercrowding: [String: Int?] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Core Request Method
    private func request(
        endpoint: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        cacheKey: String? = nil,
        cacheTTL: TimeInterval? = nil
    ) async throws -> Data {
        // Check cache first
        if let key = cacheKey, cacheTTL != nil {
            if let cached: Data = await cache.get(key) {
                return cached
            }
        }

        guard let url = URL(string: "\(AppSettings.apiBaseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        let requestKey = cacheKey ?? "\(method):\(endpoint):\(body?.description ?? "")"

        return try await inFlightRequests.getOrCreate(key: requestKey) {
            var request = URLRequest(url: url)
            request.httpMethod = method

            if let body = body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await self.session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.httpError(httpResponse.statusCode)
            }

            // Cache the result
            if let key = cacheKey, let ttl = cacheTTL {
                await self.cache.set(key, value: data, ttl: ttl)
            }

            return data
        }
    }

    // MARK: - Server Status
    func checkServerStatus() async -> Bool {
        do {
            _ = try await request(
                endpoint: "healthcheck",
                cacheKey: "healthcheck",
                cacheTTL: CacheManager.TTL.serverStatus
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Current Count
    struct CurrentCountResult {
        let count: Int
        let changed: Bool
    }

    func fetchCurrentCount(deviceId: String) async throws -> CurrentCountResult {
        // No caching or deduplication for current count - it needs to be truly live data
        // Every call makes a fresh request to the server
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/currentcount") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device_id": deviceId])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = json["current_count"] as? Int else {
            throw APIError.decodingError
        }

        let previousCount = lastCounts[deviceId]
        let changed = previousCount != count
        lastCounts[deviceId] = count

        return CurrentCountResult(count: count, changed: changed)
    }

    // MARK: - Set Count
    func setCurrentCount(deviceId: String, password: String, newCount: Int) async throws {
        _ = try await request(
            endpoint: "setcount",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "new_count": newCount]
        )

        // Clear the last known count so next fetch sees it as "changed"
        lastCounts.removeValue(forKey: deviceId)
    }

    // MARK: - Overcrowding Limit
    struct OvercrowdingResult {
        let limit: Int?
        let changed: Bool
    }

    func fetchOvercrowdingLimit(deviceId: String) async throws -> OvercrowdingResult {
        let cacheKey = "overcrowding:\(deviceId)"

        let data = try await request(
            endpoint: "get_overcrowding?device_name=\(deviceId)",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.overcrowding
        )

        let limit: Int?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let overcrowding = json["overcrowding"] as? Int {
            limit = overcrowding
        } else {
            limit = nil
        }

        let previousLimit = lastOvercrowding[deviceId] ?? nil
        let changed = previousLimit != limit
        lastOvercrowding[deviceId] = limit

        return OvercrowdingResult(limit: limit, changed: changed)
    }

    // MARK: - Connection Status
    func checkConnectionStatus(deviceId: String) async throws -> String {
        let cacheKey = "connection:\(deviceId)"

        let data = try await request(
            endpoint: "connection_status",
            method: "POST",
            body: ["device_id": deviceId],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.connectionStatus
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw APIError.decodingError
        }

        return status
    }

    // MARK: - Password Check
    func checkPassword(deviceId: String, password: String) async throws -> Bool {
        let data = try await request(
            endpoint: "check_password",
            method: "POST",
            body: ["device_id": deviceId, "password": password]
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isCorrect = json["is_password_correct"] as? Bool else {
            throw APIError.decodingError
        }

        return isCorrect
    }

    // MARK: - Available Dates
    func fetchAvailableDates(deviceId: String, password: String) async throws -> [String] {
        let cacheKey = "dates:\(deviceId)"

        let data = try await request(
            endpoint: "get_user_days",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.availableDates
        )

        let response = try JSONDecoder().decode(AvailableDatesResponse.self, from: data)
        return response.dates
    }

    // MARK: - Day Data (Parallel fetch for primary + secondary UTC dates)
    func fetchDayData(deviceId: String, password: String, utcDate: String) async throws -> [String: Double] {
        let cacheKey = "daydata:\(deviceId):\(utcDate)"

        let data = try await request(
            endpoint: "get_day_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "date": utcDate],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.dayData
        )

        let response = try JSONDecoder().decode(DayDataResponse.self, from: data)
        return response.day_data
    }

    func fetchAverageDayData(deviceId: String, password: String, utcDate: String) async throws -> [String: Double] {
        let cacheKey = "avgdaydata:\(deviceId):\(utcDate)"

        let data = try await request(
            endpoint: "get_average_day_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "date": utcDate],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.dayData
        )

        let response = try JSONDecoder().decode(AverageDayDataResponse.self, from: data)
        return response.average_day_data
    }

    // MARK: - Week Data
    func fetchWeekData(deviceId: String, password: String, date: String) async throws -> [String: Double] {
        let cacheKey = "weekdata:\(deviceId):\(date)"

        let data = try await request(
            endpoint: "get_week_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "date": date],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.weekData
        )

        let response = try JSONDecoder().decode(WeekDataResponse.self, from: data)
        return response.week_data
    }

    func fetchAverageWeekData(deviceId: String, password: String, date: String) async throws -> [String: Double] {
        let cacheKey = "avgweekdata:\(deviceId):\(date)"

        let data = try await request(
            endpoint: "get_average_week_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "date": date],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.weekData
        )

        let response = try JSONDecoder().decode(AverageWeekDataResponse.self, from: data)
        return response.average_week_data
    }

    // MARK: - Year Data
    func fetchYearData(deviceId: String, password: String, year: Int) async throws -> [String: Double] {
        let cacheKey = "yeardata:\(deviceId):\(year)"

        let data = try await request(
            endpoint: "get_year_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "year": year],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.yearData
        )

        let response = try JSONDecoder().decode(YearDataResponse.self, from: data)
        return response.year_data
    }

    func fetchAverageYearData(deviceId: String, password: String, year: Int) async throws -> [String: Double]? {
        let cacheKey = "avgyeardata:\(deviceId):\(year)"

        let data = try await request(
            endpoint: "get_average_year_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "year": year],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.yearData
        )

        let response = try JSONDecoder().decode(AverageYearDataResponse.self, from: data)
        switch response.average_year_data {
        case .data(let dict):
            return dict
        case .notAvailable:
            return nil
        }
    }

    // MARK: - Alert Check
    func checkForAlert() async throws -> Bool {
        let cacheKey = "alertcheck"

        let data = try await request(
            endpoint: "check_if_alert",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.alertCheck
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isAlert = json["is_alert"] as? Bool else {
            return false
        }

        return isAlert
    }

    func fetchAlertInfo() async throws -> (type: String, title: String, body: String, alertId: String)? {
        let data = try await request(endpoint: "get_active_alert")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alertArray = json["alert_info"] as? [[String: String]],
              let alert = alertArray.first,
              let type = alert["alert_type"],
              let title = alert["title"],
              let body = alert["body"],
              let alertId = alert["alert_id"] else {
            return nil
        }

        return (type: type, title: title, body: body, alertId: alertId)
    }

    // MARK: - App Registration & Heartbeat
    func registerApp(appId: String) async {
        _ = try? await request(
            endpoint: "register",
            method: "POST",
            body: ["app_id": appId]
        )
    }

    func sendHeartbeat(appId: String) async {
        _ = try? await request(
            endpoint: "heartbeat",
            method: "POST",
            body: ["app_id": appId]
        )
    }

    // MARK: - Location Data (Location-Centric Model)

    /// Response structure for location data from server
    struct LocationDataResponse: Codable {
        let locations: [LocationData]
    }

    struct LocationData: Codable {
        let location_name: String
        let location_address: String?
        let location_device: String
        let location_latitude: Double?
        let location_longitude: Double?
        let location_color: String?
        let location_icon: String?
        let location_current_count: Int
        let location_comparison: String
        let location_overcrowding_count: OvercrowdingValue
        let device_breakdown: [DeviceBreakdown]?

        enum OvercrowdingValue: Codable {
            case int(Int)
            case notAvailable

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let intValue = try? container.decode(Int.self) {
                    self = .int(intValue)
                } else if let stringValue = try? container.decode(String.self), stringValue == "N/A" {
                    self = .notAvailable
                } else {
                    self = .notAvailable
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .int(let value):
                    try container.encode(value)
                case .notAvailable:
                    try container.encode("N/A")
                }
            }

            var intValue: Int? {
                switch self {
                case .int(let value): return value
                case .notAvailable: return nil
                }
            }
        }
    }

    struct DeviceBreakdown: Codable {
        let device_id: String
        let device_label: String
        let count: Int
        let overcrowding: OvercrowdingValue

        enum OvercrowdingValue: Codable {
            case int(Int)
            case notAvailable

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let intValue = try? container.decode(Int.self) {
                    self = .int(intValue)
                } else if let stringValue = try? container.decode(String.self), stringValue == "N/A" {
                    self = .notAvailable
                } else {
                    self = .notAvailable
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .int(let value):
                    try container.encode(value)
                case .notAvailable:
                    try container.encode("N/A")
                }
            }

            var intValue: Int? {
                switch self {
                case .int(let value): return value
                case .notAvailable: return nil
                }
            }
        }
    }

    struct DeviceMapStatus: Codable {
        let on_map: Bool
        let is_primary: Bool
        let primary_device: String?
        let location_name: String?
    }

    /// Fetch all location data with aggregated counts and device breakdowns.
    /// This is the primary data source for the location-centric UI.
    func fetchAllLocationData() async throws -> [LocationData] {
        let cacheKey = "all_location_data"

        let data = try await request(
            endpoint: "get_all_location_data_with_extra",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.locations
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locationsArray = json["locations"] as? [[String: Any]] else {
            throw APIError.decodingError
        }

        // Manual decoding to handle the complex overcrowding type
        var locations: [LocationData] = []
        for loc in locationsArray {
            guard let name = loc["location_name"] as? String,
                  let device = loc["location_device"] as? String,
                  let currentCount = loc["location_current_count"] as? Int,
                  let comparison = loc["location_comparison"] as? String else {
                continue
            }

            let overcrowding: LocationData.OvercrowdingValue
            if let intValue = loc["location_overcrowding_count"] as? Int {
                overcrowding = .int(intValue)
            } else {
                overcrowding = .notAvailable
            }

            var deviceBreakdown: [DeviceBreakdown]? = nil
            if let breakdownArray = loc["device_breakdown"] as? [[String: Any]], !breakdownArray.isEmpty {
                deviceBreakdown = breakdownArray.compactMap { bd -> DeviceBreakdown? in
                    guard let deviceId = bd["device_id"] as? String,
                          let label = bd["device_label"] as? String,
                          let count = bd["count"] as? Int else {
                        return nil
                    }
                    let bdOvercrowding: DeviceBreakdown.OvercrowdingValue
                    if let intValue = bd["overcrowding"] as? Int {
                        bdOvercrowding = .int(intValue)
                    } else {
                        bdOvercrowding = .notAvailable
                    }
                    return DeviceBreakdown(device_id: deviceId, device_label: label, count: count, overcrowding: bdOvercrowding)
                }
            }

            locations.append(LocationData(
                location_name: name,
                location_address: loc["location_address"] as? String,
                location_device: device,
                location_latitude: loc["location_latitude"] as? Double,
                location_longitude: loc["location_longitude"] as? Double,
                location_color: loc["location_color"] as? String,
                location_icon: loc["location_icon"] as? String,
                location_current_count: currentCount,
                location_comparison: comparison,
                location_overcrowding_count: overcrowding,
                device_breakdown: deviceBreakdown
            ))
        }

        return locations
    }

    /// Check if a device is on the map and get its location information.
    /// Used to determine which location a counter belongs to.
    func getDeviceMapStatus(deviceId: String) async throws -> DeviceMapStatus {
        let cacheKey = "device_map_status:\(deviceId)"

        let data = try await request(
            endpoint: "get_device_map_status?device_id=\(deviceId)",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.locations
        )

        let status = try JSONDecoder().decode(DeviceMapStatus.self, from: data)
        return status
    }

    /// Fetch map status for multiple devices in parallel
    func fetchAllDeviceMapStatuses(deviceIds: [String]) async -> [String: DeviceMapStatus] {
        await withTaskGroup(of: (String, DeviceMapStatus?).self) { group in
            for deviceId in deviceIds {
                group.addTask {
                    let status = try? await self.getDeviceMapStatus(deviceId: deviceId)
                    return (deviceId, status)
                }
            }

            var results: [String: DeviceMapStatus] = [:]
            for await (deviceId, status) in group {
                if let status = status {
                    results[deviceId] = status
                }
            }
            return results
        }
    }

    // MARK: - Batch Operations for Multiple Users

    /// Fetch current counts for all users in parallel
    func fetchAllCurrentCounts(users: [(id: UUID, deviceId: String)]) async -> [UUID: Int] {
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for user in users {
                group.addTask {
                    let result = try? await self.fetchCurrentCount(deviceId: user.deviceId)
                    return (user.id, result?.count)
                }
            }

            var results: [UUID: Int] = [:]
            for await (id, count) in group {
                if let count = count {
                    results[id] = count
                }
            }
            return results
        }
    }

    /// Fetch overcrowding limits for all users in parallel
    func fetchAllOvercrowdingLimits(users: [(id: UUID, deviceId: String)]) async -> [UUID: Int?] {
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for user in users {
                group.addTask {
                    let result = try? await self.fetchOvercrowdingLimit(deviceId: user.deviceId)
                    return (user.id, result?.limit)
                }
            }

            var results: [UUID: Int?] = [:]
            for await (id, limit) in group {
                results[id] = limit
            }
            return results
        }
    }

    /// Fetch connection statuses for all users in parallel
    func fetchAllConnectionStatuses(users: [(id: UUID, deviceId: String)]) async -> [UUID: String] {
        await withTaskGroup(of: (UUID, String?).self) { group in
            for user in users {
                group.addTask {
                    let status = try? await self.checkConnectionStatus(deviceId: user.deviceId)
                    return (user.id, status)
                }
            }

            var results: [UUID: String] = [:]
            for await (id, status) in group {
                if let status = status {
                    results[id] = status
                }
            }
            return results
        }
    }

    /// Fetch available dates for all users in parallel and merge
    func fetchAllAvailableDates(users: [(deviceId: String, password: String)]) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            for user in users {
                group.addTask {
                    (try? await self.fetchAvailableDates(deviceId: user.deviceId, password: user.password)) ?? []
                }
            }

            var allDates = Set<String>()
            for await dates in group {
                allDates.formUnion(dates)
            }
            return Array(allDates)
        }
    }

    /// Fetch day data for multiple users in parallel and aggregate
    func fetchAggregatedDayData(
        users: [(deviceId: String, password: String)],
        utcDates: [String],
        targetLocalDate: String
    ) async -> (dayData: [String: Double], averageData: [String: Double]) {

        // Collect all results first, then aggregate (avoids async locking issues)
        let results = await withTaskGroup(of: ([String: Double], [String: Double]).self) { group -> [([String: Double], [String: Double])] in
            for user in users {
                for utcDate in utcDates {
                    group.addTask {
                        async let dayTask = self.fetchDayData(deviceId: user.deviceId, password: user.password, utcDate: utcDate)
                        async let avgTask = self.fetchAverageDayData(deviceId: user.deviceId, password: user.password, utcDate: utcDate)

                        let dayData = (try? await dayTask) ?? [:]
                        let avgData = (try? await avgTask) ?? [:]

                        // Shift to local time
                        let localDayData = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: dayData, targetLocalDate: targetLocalDate)
                        let localAvgData = TZHelper.shiftHourlyBinsUTCtoLocal(forUTCDate: utcDate, bins: avgData, targetLocalDate: targetLocalDate)

                        return (localDayData, localAvgData)
                    }
                }
            }

            var collected: [([String: Double], [String: Double])] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Aggregate results on main actor (no locking needed)
        var dayDataResults: [String: Double] = [:]
        var avgDataResults: [String: Double] = [:]
        for (dayData, avgData) in results {
            for (hour, count) in dayData {
                dayDataResults[hour, default: 0] += count
            }
            for (hour, count) in avgData {
                avgDataResults[hour, default: 0] += count
            }
        }

        return (dayDataResults, avgDataResults)
    }

    /// Fetch week data for multiple users in parallel and aggregate
    func fetchAggregatedWeekData(
        users: [(deviceId: String, password: String)],
        date: String
    ) async -> (weekData: [String: Double], averageData: [String: Double]) {

        // Collect all results first, then aggregate
        let results = await withTaskGroup(of: ([String: Double], [String: Double]).self) { group -> [([String: Double], [String: Double])] in
            for user in users {
                group.addTask {
                    async let weekTask = self.fetchWeekData(deviceId: user.deviceId, password: user.password, date: date)
                    async let avgTask = self.fetchAverageWeekData(deviceId: user.deviceId, password: user.password, date: date)

                    let weekData = (try? await weekTask) ?? [:]
                    let avgData = (try? await avgTask) ?? [:]

                    return (weekData, avgData)
                }
            }

            var collected: [([String: Double], [String: Double])] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Aggregate results
        var weekDataResults: [String: Double] = [:]
        var avgDataResults: [String: Double] = [:]
        for (weekData, avgData) in results {
            for (day, count) in weekData {
                weekDataResults[day, default: 0] += count
            }
            for (day, count) in avgData {
                avgDataResults[day, default: 0] += count
            }
        }

        return (weekDataResults, avgDataResults)
    }

    /// Fetch year data for multiple users in parallel and aggregate
    func fetchAggregatedYearData(
        users: [(deviceId: String, password: String)],
        year: Int
    ) async -> (yearData: [String: Double], averageData: [String: Double]?) {

        // Collect all results first, then aggregate
        let results = await withTaskGroup(of: ([String: Double], [String: Double]?).self) { group -> [([String: Double], [String: Double]?)] in
            for user in users {
                group.addTask {
                    async let yearTask = self.fetchYearData(deviceId: user.deviceId, password: user.password, year: year)
                    async let avgTask = self.fetchAverageYearData(deviceId: user.deviceId, password: user.password, year: year)

                    let yearData = (try? await yearTask) ?? [:]
                    let avgData = try? await avgTask

                    return (yearData, avgData)
                }
            }

            var collected: [([String: Double], [String: Double]?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Aggregate results
        var yearDataResults: [String: Double] = [:]
        var avgDataResults: [String: Double] = [:]
        var hasAnyAvgData = false
        for (yearData, avgData) in results {
            for (month, count) in yearData {
                yearDataResults[month, default: 0] += count
            }
            if let avgData = avgData {
                hasAnyAvgData = true
                for (month, count) in avgData {
                    avgDataResults[month, default: 0] += count
                }
            }
        }

        return (yearDataResults, hasAnyAvgData ? avgDataResults : nil)
    }
}

// MARK: - API Errors
enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError
    case notFound
}

// MARK: - Timezone Helper (shared utility)
enum TZHelper {
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func utcDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    static func localDate(from yyyyMMdd: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)
    }

    static func yyyyMMddUTC(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func yyyyMMddLocal(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

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

    static func shiftHourlyBinsUTCtoLocal(
        forUTCDate utcYYYYMMDD: String,
        bins: [String: Double],
        targetLocalDate: String
    ) -> [String: Double] {
        guard let utcMidnight = utcDate(from: utcYYYYMMDD),
              let targetLocalMidnight = localDate(from: targetLocalDate) else {
            return [:]
        }

        var utcCalendar = Calendar(identifier: .iso8601)
        utcCalendar.timeZone = utc

        var localCalendar = Calendar(identifier: .iso8601)
        localCalendar.timeZone = .current

        var out: [String: Double] = [:]

        for (hourKey, value) in bins {
            guard let utcHour = Int(hourKey), utcHour >= 0, utcHour < 24 else { continue }

            guard let utcTimestamp = utcCalendar.date(bySettingHour: utcHour, minute: 0, second: 0, of: utcMidnight) else {
                continue
            }

            let localComponents = localCalendar.dateComponents([.year, .month, .day, .hour], from: utcTimestamp)
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

    static func utcDatesToLocalDates(_ utcDates: [String]) -> [String] {
        var localDatesSet = Set<String>()
        let todayLocal = yyyyMMddLocal(from: Date())

        for utcDate in utcDates {
            guard let utcMidnight = self.utcDate(from: utcDate) else { continue }

            var localCalendar = Calendar(identifier: .iso8601)
            localCalendar.timeZone = .current

            let localAtUTCMidnight = localCalendar.dateComponents([.year, .month, .day], from: utcMidnight)
            if let y = localAtUTCMidnight.year, let m = localAtUTCMidnight.month, let d = localAtUTCMidnight.day {
                let localDateStr = String(format: "%04d-%02d-%02d", y, m, d)
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
                    if localDateStr <= todayLocal {
                        localDatesSet.insert(localDateStr)
                    }
                }
            }
        }

        return Array(localDatesSet)
    }
}
