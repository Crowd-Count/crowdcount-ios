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
        static let serverStatus: TimeInterval = 2.0
        static let currentCount: TimeInterval = 0.5
        static let overcrowding: TimeInterval = 4.0
        static let connectionStatus: TimeInterval = 2.0
        static let availableDates: TimeInterval = 60.0
        static let dayData: TimeInterval = 30.0
        static let weekData: TimeInterval = 60.0
        static let yearData: TimeInterval = 120.0
        static let alertCheck: TimeInterval = 30.0
        static let locations: TimeInterval = 30.0
        static let promotionPricing: TimeInterval = 60.0
        static let posStatus: TimeInterval = 30.0
        static let posInsights: TimeInterval = 60.0
        static let posTransactions: TimeInterval = 30.0
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

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// Headers that identify this app version to the server for alert targeting.
    private var versionHeaders: [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return ["X-App-Version": version]
    }

    // MARK: - Credentials Helper

    /// Build credentials array for location endpoints from Device objects
    func credentialsBody(from devices: [Device], filterTo deviceIds: [String]) -> [[String: String]] {
        devices.filter { deviceIds.contains($0.deviceId) }
            .map { ["device_id": $0.deviceId, "password": $0.password] }
    }

    // MARK: - Core Request Method
    private func request(
        endpoint: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        cacheKey: String? = nil,
        cacheTTL: TimeInterval? = nil,
        credentials: (deviceId: String, password: String)? = nil,
        idempotent: Bool = false,
        additionalHeaders: [String: String]? = nil
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

            var bodyStr = ""
            if let body = body {
                let bodyData = try? JSONSerialization.data(withJSONObject: body)
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bodyData = bodyData {
                    bodyStr = String(data: bodyData, encoding: .utf8) ?? ""
                }
            }

            // Sign request if credentials provided
            if let creds = credentials {
                let path = url.path
                let sigHeaders = CryptoHelper.signRequest(
                    deviceId: creds.deviceId,
                    password: creds.password,
                    method: method,
                    path: path.isEmpty ? "/\(endpoint)" : path,
                    body: bodyStr
                )
                for (key, value) in sigHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            // Add idempotency key for mutating requests
            if idempotent {
                request.setValue(CryptoHelper.generateIdempotencyKey(), forHTTPHeaderField: "Idempotency-Key")
            }

            // Add any extra headers (e.g. X-App-Version)
            if let additionalHeaders = additionalHeaders {
                for (key, value) in additionalHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
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

    func fetchCurrentCount(deviceId: String, password: String) async throws -> CurrentCountResult {
        let data = try await request(
            endpoint: "currentcount",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password)
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = json["current_count"] as? Int else {
            throw APIError.decodingError
        }

        let previousCount = lastCounts[deviceId]
        let changed = previousCount != count
        lastCounts[deviceId] = count

        return CurrentCountResult(count: count, changed: changed)
    }

    // MARK: - Add/Sub Count (single device auth)

    func addToCount(deviceId: String, password: String, amount: Int) async throws {
        _ = try await request(
            endpoint: "add_to_count",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "count_to_add": amount],
            credentials: (deviceId, password),
            idempotent: true
        )
        lastCounts.removeValue(forKey: deviceId)
    }

    func subFromCount(deviceId: String, password: String, amount: Int) async throws {
        _ = try await request(
            endpoint: "sub_from_count",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "count_to_sub": amount],
            credentials: (deviceId, password),
            idempotent: true
        )
        lastCounts.removeValue(forKey: deviceId)
    }

    // MARK: - Location Count

    func locationAddToCount(locationId: String, credentials: [[String: String]], signingDevice: (String, String), amount: Int) async throws {
        _ = try await request(
            endpoint: "location/add_to_count",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials, "count_to_add": amount],
            credentials: signingDevice,
            idempotent: true
        )
    }

    func locationSubFromCount(locationId: String, credentials: [[String: String]], signingDevice: (String, String), amount: Int) async throws {
        _ = try await request(
            endpoint: "location/sub_from_count",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials, "count_to_sub": amount],
            credentials: signingDevice,
            idempotent: true
        )
    }

    // MARK: - Set Count (legacy, kept for device settings reset)
    func setCurrentCount(deviceId: String, password: String, newCount: Int) async throws {
        _ = try await request(
            endpoint: "setcount",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "new_count": newCount],
            credentials: (deviceId, password),
            idempotent: true
        )
        lastCounts.removeValue(forKey: deviceId)
    }

    // MARK: - Connection Status
    func checkConnectionStatus(deviceId: String, password: String) async throws -> String {
        let cacheKey = "connection:\(deviceId)"

        let data = try await request(
            endpoint: "connection_status",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.connectionStatus,
            credentials: (deviceId, password)
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
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password)
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isCorrect = json["is_password_correct"] as? Bool else {
            throw APIError.decodingError
        }

        return isCorrect
    }

    // MARK: - Location Endpoints

    /// Get all locations a device belongs to (single device auth)
    func getLocationsForDevice(deviceId: String, password: String) async throws -> [LocationResponse] {
        let data = try await request(
            endpoint: "get_locations_for_device",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password)
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locationsArray = json["locations"] as? [[String: Any]] else {
            throw APIError.decodingError
        }

        return locationsArray.compactMap { LocationResponse(from: $0) }
    }

    /// Get a specific location's details (credentials auth)
    func getLocation(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> LocationResponse {
        let data = try await request(
            endpoint: "get_location",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = LocationResponse(from: json) else {
            throw APIError.decodingError
        }

        return response
    }

    /// Update a location's name and/or overcrowding limit
    func updateLocation(locationId: String, name: String? = nil, overcrowdingLimit: Int? = nil, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        var body: [String: Any] = [
            "location_id": locationId,
            "credentials": credentials
        ]
        if let name = name {
            body["name"] = name
        }
        if let limit = overcrowdingLimit {
            body["overcrowding_limit"] = limit
        }

        _ = try await request(
            endpoint: "update_location",
            method: "POST",
            body: body,
            credentials: signingDevice,
            idempotent: true
        )
    }

    /// Add a device to a location (existing devices only for auth)
    func addDeviceToLocation(locationId: String, newDeviceId: String, newDevicePassword: String, label: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "add_device_to_location",
            method: "POST",
            body: [
                "location_id": locationId,
                "new_device_id": newDeviceId,
                "new_device_password": newDevicePassword,
                "label": label,
                "credentials": credentials
            ],
            credentials: signingDevice,
            idempotent: true
        )
    }

    /// Remove a device from a location (DEPRECATED — use replaceLocation)
    func removeDeviceFromLocation(locationId: String, targetDeviceId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "remove_device_from_location",
            method: "POST",
            body: [
                "location_id": locationId,
                "target_device_id": targetDeviceId,
                "credentials": credentials
            ],
            credentials: signingDevice,
            idempotent: true
        )
    }

    /// Replace a location with a new device set, preserving metadata.
    /// Returns the new location_id (may equal old if device set unchanged).
    func replaceLocation(locationId: String, credentials: [[String: String]], deviceLabels: [String: String]? = nil, signingDevice: (String, String)) async throws -> String {
        var body: [String: Any] = [
            "location_id": locationId,
            "credentials": credentials
        ]
        if let labels = deviceLabels {
            body["device_labels"] = labels
        }

        let data = try await request(
            endpoint: "replace_location",
            method: "POST",
            body: body,
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newLocationId = json["location_id"] as? String else {
            throw APIError.decodingError
        }

        return newLocationId
    }

    /// Delete a location
    func deleteLocation(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "delete_location",
            method: "POST",
            body: [
                "location_id": locationId,
                "credentials": credentials
            ],
            credentials: signingDevice,
            idempotent: true
        )
    }

    /// Create a new location — returns the new location_id
    func createLocation(name: String? = nil, credentials: [[String: String]], deviceLabels: [String: String]? = nil, signingDevice: (String, String)) async throws -> String {
        var body: [String: Any] = [
            "credentials": credentials
        ]
        if let name = name {
            body["name"] = name
        }
        if let labels = deviceLabels {
            body["device_labels"] = labels
        }

        let data = try await request(
            endpoint: "create_location",
            method: "POST",
            body: body,
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locationId = json["location_id"] as? String else {
            throw APIError.decodingError
        }

        return locationId
    }

    // MARK: - Location Overcrowding Notifications

    func registerLocationOvercrowdingNotification(locationId: String, appId: String, signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "register_location_overcrowding_notification",
            method: "POST",
            body: ["location_id": locationId, "app_id": appId, "device_id": signingDevice.0, "password": signingDevice.1],
            credentials: signingDevice,
            idempotent: true
        )
    }

    func unregisterLocationOvercrowdingNotification(locationId: String, appId: String, signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "unregister_location_overcrowding_notification",
            method: "POST",
            body: ["location_id": locationId, "app_id": appId, "device_id": signingDevice.0, "password": signingDevice.1],
            credentials: signingDevice,
            idempotent: true
        )
    }

    func checkLocationOvercrowdingNotification(locationId: String, appId: String) async throws -> Bool {
        let data = try await request(
            endpoint: "check_location_overcrowding_notification?location_id=\(locationId)&app_id=\(appId)"
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = json["notifications_enabled"] as? Bool else {
            return false
        }

        return enabled
    }

    // MARK: - Location History Endpoints
    //
    // All location history endpoints return {"data": {...}} from the server's
    // generic _location_history_handler. We parse them uniformly.

    private func parseLocationHistoryData(_ data: Data) throws -> [String: Double] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Double] else {
            // Server may return empty dict or null values — return empty
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                // Handle mixed Int/Double values
                var result: [String: Double] = [:]
                for (key, value) in dataDict {
                    if let d = value as? Double { result[key] = d }
                    else if let i = value as? Int { result[key] = Double(i) }
                }
                return result
            }
            return [:]
        }
        return dataDict
    }

    func fetchLocationDayData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_day_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials],
            cacheKey: "loc_daydata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.dayData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageDayData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_average_day_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials],
            cacheKey: "loc_avgdaydata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.dayData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationWeekData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_week_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials, "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60],
            cacheKey: "loc_weekdata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.weekData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageWeekData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_average_week_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials, "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60],
            cacheKey: "loc_avgweekdata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.weekData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationYearData(locationId: String, year: Int, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_year_data",
            method: "POST",
            body: ["location_id": locationId, "year": year, "credentials": credentials],
            cacheKey: "loc_yeardata:\(locationId):\(year)",
            cacheTTL: CacheManager.TTL.yearData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageYearData(locationId: String, year: Int, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double]? {
        let data = try await request(
            endpoint: "get_location_average_year_data",
            method: "POST",
            body: ["location_id": locationId, "year": year, "credentials": credentials],
            cacheKey: "loc_avgyeardata:\(locationId):\(year)",
            cacheTTL: CacheManager.TTL.yearData,
            credentials: signingDevice
        )
        // Server returns {"data": "N/A"} when insufficient data
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataVal = json["data"] as? String, dataVal == "N/A" {
            return nil
        }
        return try parseLocationHistoryData(data)
    }

    // MARK: - Location Entry History Endpoints

    func fetchLocationEntryDayData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_entry_day_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials],
            cacheKey: "loc_entrydaydata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.dayData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageEntryDayData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_average_entry_day_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials],
            cacheKey: "loc_avgEntrydaydata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.dayData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationEntryWeekData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_entry_week_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials, "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60],
            cacheKey: "loc_entryweekdata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.weekData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageEntryWeekData(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_average_entry_week_data",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials, "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60],
            cacheKey: "loc_avgentryweekdata:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.weekData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationEntryYearData(locationId: String, year: Int, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_entry_year_data",
            method: "POST",
            body: ["location_id": locationId, "year": year, "credentials": credentials],
            cacheKey: "loc_entryyeardata:\(locationId):\(year)",
            cacheTTL: CacheManager.TTL.yearData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationAverageEntryYearData(locationId: String, year: Int, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double]? {
        let data = try await request(
            endpoint: "get_location_average_entry_year_data",
            method: "POST",
            body: ["location_id": locationId, "year": year, "credentials": credentials],
            cacheKey: "loc_avgentryyeardata:\(locationId):\(year)",
            cacheTTL: CacheManager.TTL.yearData,
            credentials: signingDevice
        )
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataVal = json["data"] as? String, dataVal == "N/A" {
            return nil
        }
        return try parseLocationHistoryData(data)
    }

    // MARK: - Location Dwell Time Endpoints

    func fetchLocationDwellTimeWeek(locationId: String, date: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_dwell_time_week",
            method: "POST",
            body: ["location_id": locationId, "date": date, "credentials": credentials],
            cacheKey: "loc_dwelltimeweek:\(locationId):\(date)",
            cacheTTL: CacheManager.TTL.weekData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    func fetchLocationDwellTimeYear(locationId: String, year: Int, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String: Double] {
        let data = try await request(
            endpoint: "get_location_dwell_time_year",
            method: "POST",
            body: ["location_id": locationId, "year": year, "credentials": credentials],
            cacheKey: "loc_dwelltimeyear:\(locationId):\(year)",
            cacheTTL: CacheManager.TTL.yearData,
            credentials: signingDevice
        )
        return try parseLocationHistoryData(data)
    }

    // MARK: - Location Bundle Endpoints

    struct InsightsBundleResponse {
        let dayView: [String: Double]
        let averageDayView: [String: Double]
        let entryDayView: [String: Double]
        let averageEntryDayView: [String: Double]
        let dayView2: [String: Double]?
        let averageDayView2: [String: Double]?
        let entryDayView2: [String: Double]?
        let averageEntryDayView2: [String: Double]?
        let weekView: [String: Double]
        let averageWeekView: [String: Double]
        let entryWeekView: [String: Double]
        let averageEntryWeekView: [String: Double]
        let yearView: [String: Double]
        let averageYearView: [String: Double]?
        let entryYearView: [String: Double]
        let averageEntryYearView: [String: Double]?
        let dwellTimeMinutes: Double?
    }

    struct HistoryBundleResponse {
        let dayView: [String: Double]
        let averageDayView: [String: Double]
        let dayView2: [String: Double]?
        let averageDayView2: [String: Double]?
        let weekView: [String: Double]
        let averageWeekView: [String: Double]
        let yearView: [String: Double]
        let averageYearView: [String: Double]?
    }

    private func parseBundleDict(_ json: [String: Any], key: String) -> [String: Double] {
        guard let dict = json[key] as? [String: Any] else { return [:] }
        var result: [String: Double] = [:]
        for (k, v) in dict {
            if let d = v as? Double { result[k] = d }
            else if let i = v as? Int { result[k] = Double(i) }
        }
        return result
    }

    private func parseBundleDictOptional(_ json: [String: Any], key: String) -> [String: Double]? {
        // Server returns null or "N/A" for insufficient data
        if json[key] is NSNull { return nil }
        if let str = json[key] as? String, str == "N/A" { return nil }
        let result = parseBundleDict(json, key: key)
        return result.isEmpty ? nil : result
    }

    func fetchLocationInsightsBundle(
        locationId: String,
        date: String,
        date2: String?,
        weekDate: String,
        year: Int,
        credentials: [[String: String]],
        signingDevice: (String, String)
    ) async throws -> InsightsBundleResponse {
        var body: [String: Any] = [
            "location_id": locationId,
            "credentials": credentials,
            "date": date,
            "week_date": weekDate,
            "year": year,
            "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60
        ]
        if let date2 = date2 {
            body["date2"] = date2
        }

        let data = try await request(
            endpoint: "get_location_insights_bundle",
            method: "POST",
            body: body,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        // Parse dwell time (number or empty dict from _safe_view)
        let dwellTime: Double?
        if let d = json["dwell_time_view"] as? Double {
            dwellTime = d
        } else if let i = json["dwell_time_view"] as? Int {
            dwellTime = Double(i)
        } else {
            dwellTime = nil
        }

        return InsightsBundleResponse(
            dayView: parseBundleDict(json, key: "day_view"),
            averageDayView: parseBundleDict(json, key: "average_day_view"),
            entryDayView: parseBundleDict(json, key: "entry_day_view"),
            averageEntryDayView: parseBundleDict(json, key: "average_entry_day_view"),
            dayView2: date2 != nil ? parseBundleDict(json, key: "day_view_2") : nil,
            averageDayView2: date2 != nil ? parseBundleDict(json, key: "average_day_view_2") : nil,
            entryDayView2: date2 != nil ? parseBundleDict(json, key: "entry_day_view_2") : nil,
            averageEntryDayView2: date2 != nil ? parseBundleDict(json, key: "average_entry_day_view_2") : nil,
            weekView: parseBundleDict(json, key: "week_view"),
            averageWeekView: parseBundleDict(json, key: "average_week_view"),
            entryWeekView: parseBundleDict(json, key: "entry_week_view"),
            averageEntryWeekView: parseBundleDict(json, key: "average_entry_week_view"),
            yearView: parseBundleDict(json, key: "year_view"),
            averageYearView: parseBundleDictOptional(json, key: "average_year_view"),
            entryYearView: parseBundleDict(json, key: "entry_year_view"),
            averageEntryYearView: parseBundleDictOptional(json, key: "average_entry_year_view"),
            dwellTimeMinutes: dwellTime
        )
    }

    func fetchLocationHistoryBundle(
        locationId: String,
        date: String,
        date2: String?,
        weekDate: String,
        year: Int,
        dataType: String,
        credentials: [[String: String]],
        signingDevice: (String, String)
    ) async throws -> HistoryBundleResponse {
        var body: [String: Any] = [
            "location_id": locationId,
            "credentials": credentials,
            "date": date,
            "week_date": weekDate,
            "year": year,
            "data_type": dataType,
            "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60
        ]
        if let date2 = date2 {
            body["date2"] = date2
        }

        let data = try await request(
            endpoint: "get_location_history_bundle",
            method: "POST",
            body: body,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return HistoryBundleResponse(
            dayView: parseBundleDict(json, key: "day_view"),
            averageDayView: parseBundleDict(json, key: "average_day_view"),
            dayView2: date2 != nil ? parseBundleDict(json, key: "day_view_2") : nil,
            averageDayView2: date2 != nil ? parseBundleDict(json, key: "average_day_view_2") : nil,
            weekView: parseBundleDict(json, key: "week_view"),
            averageWeekView: parseBundleDict(json, key: "average_week_view"),
            yearView: parseBundleDict(json, key: "year_view"),
            averageYearView: parseBundleDictOptional(json, key: "average_year_view")
        )
    }

    // MARK: - Detailed Day Data (15-min intervals for CSV downloads)

    struct DayDataDetailedResponse {
        let data: [String: Double]
        let average: [String: Double]
    }

    func fetchLocationDayDataDetailed(
        locationId: String,
        date: String,
        dataType: String,
        credentials: [[String: String]],
        signingDevice: (String, String)
    ) async throws -> DayDataDetailedResponse {
        let body: [String: Any] = [
            "location_id": locationId,
            "credentials": credentials,
            "date": date,
            "data_type": dataType,
            "tz_offset_minutes": TimeZone.current.secondsFromGMT() / 60
        ]

        let data = try await request(
            endpoint: "get_location_day_data_detailed",
            method: "POST",
            body: body,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return DayDataDetailedResponse(
            data: parseBundleDict(json, key: "data"),
            average: parseBundleDict(json, key: "average")
        )
    }

    // MARK: - Location Available Dates

    /// Fetches available dates for a location via the server-level endpoint
    func fetchLocationAvailableDates(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> [String] {
        let data = try await request(
            endpoint: "get_location_available_dates",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            cacheKey: "loc_dates:\(locationId)",
            cacheTTL: CacheManager.TTL.availableDates,
            credentials: signingDevice
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dates = json["dates"] as? [String] else {
            return []
        }
        return dates
    }

    // MARK: - Alert Check
    func checkForAlert() async throws -> Bool {
        let cacheKey = "alertcheck"

        let data = try await request(
            endpoint: "check_if_alert",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.alertCheck,
            additionalHeaders: versionHeaders
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isAlert = json["is_alert"] as? Bool else {
            return false
        }

        return isAlert
    }

    func fetchAlertInfo() async throws -> (type: String, title: String, body: String, alertId: String)? {
        let data = try await request(
            endpoint: "get_active_alert",
            additionalHeaders: versionHeaders
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alertArray = json["alert_info"] as? [[String: Any]],
              let alert = alertArray.first,
              let type = alert["alert_type"] as? String,
              let title = alert["title"] as? String,
              let body = alert["body"] as? String,
              let alertId = alert["alert_id"] as? String else {
            return nil
        }

        return (type: type, title: title, body: body, alertId: alertId)
    }

    // MARK: - Popular Times

    func fetchPopularTimes(locationId: String) async throws -> PopularTimesData? {
        let data = try await request(
            endpoint: "get_popular_times?location_id=\(locationId)",
            cacheKey: "popular_times_\(locationId)",
            cacheTTL: 300
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let popularTimes = json["popular_times"] as? [String: Any],
              let dayOfWeek = json["day_of_week"] as? String else {
            return nil
        }

        var hourlyAverages: [String: Double] = [:]
        for (key, value) in popularTimes {
            if let doubleVal = value as? Double {
                hourlyAverages[key] = doubleVal
            } else if let intVal = value as? Int {
                hourlyAverages[key] = Double(intVal)
            }
        }

        let busynessLevel = json["busyness_level"] as? Int

        return PopularTimesData(hourlyAveragesUTC: hourlyAverages, dayOfWeek: dayOfWeek, busynessLevel: busynessLevel)
    }

    // MARK: - Promotion Pricing

    func fetchPromotionPricing() async throws -> Double {
        let cacheKey = "promotionPricing"

        let data = try await request(
            endpoint: "get-promotion-pricing",
            cacheKey: cacheKey,
            cacheTTL: CacheManager.TTL.promotionPricing
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pricePerHour = json["price_per_hour"] as? Double else {
            return 5.0
        }

        return pricePerHour
    }

    // MARK: - Reset Schedule

    struct ResetSchedule {
        let locationId: String
        let resetHour: Int
        let resetMinute: Int
        let timezone: String
    }

    private func parseResetSchedule(from json: [String: Any]) -> ResetSchedule? {
        guard let locationId = json["location_id"] as? String,
              let resetHour = json["reset_hour"] as? Int,
              let resetMinute = json["reset_minute"] as? Int,
              let timezone = json["timezone"] as? String else {
            return nil
        }
        return ResetSchedule(locationId: locationId, resetHour: resetHour, resetMinute: resetMinute, timezone: timezone)
    }

    func fetchResetSchedule(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> ResetSchedule? {
        let data = try await request(
            endpoint: "get_reset_schedule",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        // Server returns {"schedule": null} when no schedule exists
        if json["schedule"] is NSNull || (json["schedule"] == nil && json["location_id"] == nil) {
            return nil
        }

        // Server returns schedule fields at top level when schedule exists
        return parseResetSchedule(from: json)
    }

    func setResetSchedule(locationId: String, hour: Int, minute: Int, timezone: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> ResetSchedule {
        let data = try await request(
            endpoint: "set_reset_schedule",
            method: "POST",
            body: [
                "location_id": locationId,
                "credentials": credentials,
                "reset_hour": hour,
                "reset_minute": minute,
                "timezone": timezone
            ],
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schedule = parseResetSchedule(from: json) else {
            throw APIError.decodingError
        }

        return schedule
    }

    func deleteResetSchedule(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "delete_reset_schedule",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice,
            idempotent: true
        )
    }

    // MARK: - Closing Time

    struct ClosingTimeDay {
        let dayOfWeek: Int      // 0=Mon..6=Sun
        let closeHour: Int
        let closeMinute: Int
        let openHour: Int
        let openMinute: Int
    }

    struct ClosingTimeSchedule {
        let locationId: String
        let timezone: String
        let days: [ClosingTimeDay]
    }

    private func parseClosingTimeSchedule(from json: [String: Any]) -> ClosingTimeSchedule? {
        guard let locationId = json["location_id"] as? String,
              let timezone = json["timezone"] as? String,
              let daysArray = json["days"] as? [[String: Any]] else {
            return nil
        }

        let days = daysArray.compactMap { dayDict -> ClosingTimeDay? in
            guard let dayOfWeek = dayDict["day_of_week"] as? Int,
                  let closeHour = dayDict["close_hour"] as? Int,
                  let closeMinute = dayDict["close_minute"] as? Int,
                  let openHour = dayDict["open_hour"] as? Int,
                  let openMinute = dayDict["open_minute"] as? Int else {
                return nil
            }
            return ClosingTimeDay(dayOfWeek: dayOfWeek, closeHour: closeHour, closeMinute: closeMinute, openHour: openHour, openMinute: openMinute)
        }

        return ClosingTimeSchedule(locationId: locationId, timezone: timezone, days: days)
    }

    func fetchClosingTime(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> ClosingTimeSchedule? {
        let data = try await request(
            endpoint: "get_closing_time",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        // Server returns {"closing_time": null} when no schedule exists
        if json["closing_time"] is NSNull || (json["closing_time"] == nil && json["location_id"] == nil) {
            return nil
        }

        return parseClosingTimeSchedule(from: json)
    }

    func setClosingTime(locationId: String, timezone: String, days: [ClosingTimeDay], credentials: [[String: String]], signingDevice: (String, String)) async throws -> ClosingTimeSchedule {
        let daysPayload: [[String: Any]] = days.map { day in
            [
                "day_of_week": day.dayOfWeek,
                "close_hour": day.closeHour,
                "close_minute": day.closeMinute,
                "open_hour": day.openHour,
                "open_minute": day.openMinute
            ]
        }

        let data = try await request(
            endpoint: "set_closing_time",
            method: "POST",
            body: [
                "location_id": locationId,
                "credentials": credentials,
                "timezone": timezone,
                "days": daysPayload
            ],
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schedule = parseClosingTimeSchedule(from: json) else {
            throw APIError.decodingError
        }

        return schedule
    }

    func deleteClosingTime(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "delete_closing_time",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice,
            idempotent: true
        )
    }

    // MARK: - Device Settings

    func getDirectionFlipped(deviceId: String, password: String) async throws -> Bool {
        let data = try await request(
            endpoint: "get_direction_flipped",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password)
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flipped = json["direction_flipped"] as? Bool else {
            throw APIError.decodingError
        }

        return flipped
    }

    func setDirectionFlipped(deviceId: String, password: String, flipped: Bool) async throws {
        _ = try await request(
            endpoint: "set_direction_flipped",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "direction_flipped": flipped],
            credentials: (deviceId, password),
            idempotent: true
        )
    }

    func resetDeviceData(deviceId: String, password: String) async throws {
        _ = try await request(
            endpoint: "reset_device_data",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password),
            idempotent: true
        )
    }

    func resetLocationData(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws {
        _ = try await request(
            endpoint: "reset_location_data",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice,
            idempotent: true
        )
    }

    // MARK: - App Version Reporting

    func reportAppVersion(deviceId: String, password: String) async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let commitHash = "\(version)-\(build)-ios"
        _ = try? await request(
            endpoint: "report_version",
            method: "POST",
            body: ["device_id": deviceId, "password": password, "commit_hash": commitHash],
            credentials: (deviceId, password),
            idempotent: true
        )
    }

    // MARK: - App Registration & Heartbeat
    func registerApp(appId: String) async {
        var body: [String: Any] = ["app_id": appId]
        if let deviceToken = UserDefaults.standard.string(forKey: "deviceToken") {
            body["device_token"] = deviceToken
        }
        _ = try? await request(
            endpoint: "register",
            method: "POST",
            body: body,
            idempotent: true
        )
    }

    func sendHeartbeat(appId: String) async {
        var body: [String: Any] = ["app_id": appId]
        if let deviceToken = UserDefaults.standard.string(forKey: "deviceToken") {
            body["device_token"] = deviceToken
        }
        _ = try? await request(
            endpoint: "heartbeat",
            method: "POST",
            body: body,
            idempotent: true
        )
    }

    // MARK: - POS Endpoints

    func fetchPOSStatus(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> POSConnectionInfo {
        let data = try await request(
            endpoint: "pos/status",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            cacheKey: "pos_status:\(locationId)",
            cacheTTL: CacheManager.TTL.posStatus,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return POSConnectionInfo.from(json)
    }

    func startPOSOAuth(provider: String, locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> String {
        let data = try await request(
            endpoint: "pos/start_oauth",
            method: "POST",
            body: [
                "provider": provider,
                "location_id": locationId,
                "credentials": credentials,
                "mobile": true
            ],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthURL = json["oauth_url"] as? String else {
            throw APIError.decodingError
        }

        return oauthURL
    }

    func checkExistingPOSAccount(deviceId: String, password: String) async throws -> (hasAccount: Bool, posAccountId: String?, merchantId: String?, provider: String?) {
        let data = try await request(
            endpoint: "pos/check_existing_account",
            method: "POST",
            body: ["device_id": deviceId, "password": password],
            credentials: (deviceId, password)
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return (
            hasAccount: json["has_account"] as? Bool ?? false,
            posAccountId: json["pos_account_id"] as? String,
            merchantId: json["merchant_id"] as? String,
            provider: json["provider"] as? String
        )
    }

    func listPOSLocations(posAccountId: String, signingDevice: (String, String)) async throws -> [POSStoreLocation] {
        let data = try await request(
            endpoint: "pos/list_locations",
            method: "POST",
            body: [
                "pos_account_id": posAccountId,
                "device_id": signingDevice.0,
                "password": signingDevice.1
            ],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locations = json["locations"] as? [[String: Any]] else {
            throw APIError.decodingError
        }

        return locations.map { POSStoreLocation.from($0) }
    }

    func connectPOS(locationId: String, posAccountId: String, posLocationId: String, posLocationName: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> Bool {
        let data = try await request(
            endpoint: "pos/connect",
            method: "POST",
            body: [
                "location_id": locationId,
                "pos_account_id": posAccountId,
                "pos_location_id": posLocationId,
                "pos_location_name": posLocationName,
                "credentials": credentials
            ],
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        // Invalidate cached POS status
        await cache.invalidate("pos_status:\(locationId)")

        return json["success"] as? Bool ?? false
    }

    func disconnectPOS(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> Bool {
        let data = try await request(
            endpoint: "pos/disconnect",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            credentials: signingDevice,
            idempotent: true
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        // Invalidate cached POS status and data
        await cache.invalidate("pos_status:\(locationId)")
        await cache.invalidatePrefix("pos_insights:\(locationId)")
        await cache.invalidatePrefix("pos_tx:\(locationId)")

        return json["success"] as? Bool ?? false
    }

    func fetchPOSInsights(locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> POSInsightsResponse {
        let data = try await request(
            endpoint: "pos/insights",
            method: "POST",
            body: ["location_id": locationId, "credentials": credentials],
            cacheKey: "pos_insights:\(locationId)",
            cacheTTL: CacheManager.TTL.posInsights,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return POSInsightsResponse.from(json)
    }

    func fetchPOSTransactions(locationId: String, startDate: String, endDate: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> POSTransactionData {
        let data = try await request(
            endpoint: "pos/transactions",
            method: "POST",
            body: [
                "location_id": locationId,
                "start_date": startDate,
                "end_date": endDate,
                "credentials": credentials
            ],
            cacheKey: "pos_tx:\(locationId):\(startDate):\(endDate)",
            cacheTTL: CacheManager.TTL.posTransactions,
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return POSTransactionData.from(json)
    }

    func sandboxConnectPOS(accessToken: String, locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async throws -> (posAccountId: String, merchantId: String) {
        let data = try await request(
            endpoint: "pos/sandbox_connect",
            method: "POST",
            body: [
                "access_token": accessToken,
                "location_id": locationId,
                "credentials": credentials
            ],
            credentials: signingDevice
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let posAccountId = json["pos_account_id"] as? String,
              let merchantId = json["merchant_id"] as? String else {
            throw APIError.decodingError
        }

        // Invalidate cached POS status
        await cache.invalidate("pos_status:\(locationId)")

        return (posAccountId: posAccountId, merchantId: merchantId)
    }
}

// MARK: - Location Response

struct LocationResponse {
    let locationId: String
    let locationName: String
    let deviceIds: [String]
    let isAuto: Bool
    let overcrowdingLimit: Int?
    let currentCount: Int?
    let isOnMap: Bool
    let mapIcon: String?
    let mapColor: String?
    let isClosed: Bool

    init?(from dict: [String: Any]) {
        guard let id = dict["location_id"] as? String else { return nil }
        self.locationId = id
        self.locationName = dict["location_name"] as? String ?? id
        // devices field is [[device_id, label], ...] tuples
        if let devices = dict["devices"] as? [[Any]] {
            self.deviceIds = devices.compactMap { $0.first as? String }
        } else {
            self.deviceIds = []
        }
        self.isAuto = (dict["is_auto"] as? Int) == 1
        self.overcrowdingLimit = dict["overcrowding_limit"] as? Int
        self.currentCount = dict["current_count"] as? Int
        self.isOnMap = (dict["on_map"] as? Int) == 1
        self.mapIcon = dict["location_icon"] as? String
        self.mapColor = dict["location_color"] as? String
        self.isClosed = dict["is_closed"] as? Bool ?? false
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
            // Positive offset (e.g. UTC+5): local midnight = previous UTC date.
            // Local day spans two UTC dates: utcAtLocalMidnight and the next UTC day.
            let calendar = Calendar(identifier: .iso8601)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: localMidnight) {
                let nextUTCDate = yyyyMMddUTC(from: nextDay)
                return (utcAtLocalMidnight, nextUTCDate)
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
