import Foundation

/// Caches pre-fetched insights bundle responses so LocationHistoricView
/// can display data instantly when the user navigates to Count Analytics.
/// Populated on app launch after auto-login; consumed once by the view.
class HistoryPrefetchCache {
    static let shared = HistoryPrefetchCache()

    private var bundles: [String: APIService.InsightsBundleResponse] = [:]
    private var dates: [String: [String]] = [:]
    private let lock = NSLock()

    func set(locationId: String, bundle: APIService.InsightsBundleResponse) {
        lock.lock()
        bundles[locationId] = bundle
        lock.unlock()
    }

    func get(locationId: String) -> APIService.InsightsBundleResponse? {
        lock.lock()
        let result = bundles[locationId]
        lock.unlock()
        return result
    }

    func setDates(locationId: String, dates: [String]) {
        lock.lock()
        self.dates[locationId] = dates
        lock.unlock()
    }

    func getDates(locationId: String) -> [String]? {
        lock.lock()
        let result = dates[locationId]
        lock.unlock()
        return result
    }

    func remove(locationId: String) {
        lock.lock()
        bundles.removeValue(forKey: locationId)
        dates.removeValue(forKey: locationId)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        bundles.removeAll()
        dates.removeAll()
        lock.unlock()
    }
}
