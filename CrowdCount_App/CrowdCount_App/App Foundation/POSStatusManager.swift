import Foundation
import SwiftUI

/// Manages POS connection status per location. Singleton pattern (like NicknameManager).
@MainActor
class POSStatusManager: ObservableObject {
    static let shared = POSStatusManager()

    @Published private(set) var statusMap: [String: POSConnectionInfo] = [:]
    @Published private(set) var isLoading: Bool = false

    private let apiService = APIService.shared

    private init() {}

    // MARK: - Public Methods

    /// Get cached POS status for a location
    func getStatus(for locationId: String) -> POSConnectionInfo? {
        statusMap[locationId]
    }

    /// Check if a location has POS connected
    func isConnected(for locationId: String) -> Bool {
        statusMap[locationId]?.connected ?? false
    }

    /// Refresh POS status for a single location
    func refreshStatus(for locationId: String, credentials: [[String: String]], signingDevice: (String, String)) async {
        do {
            let status = try await apiService.fetchPOSStatus(
                locationId: locationId,
                credentials: credentials,
                signingDevice: signingDevice
            )
            statusMap[locationId] = status
        } catch {
            // Silently handle — POS is optional
        }
    }

    /// Refresh POS status for all locations. Called from ContentView on login.
    func refreshAllStatuses(locations: [AppLocation], devices: [Device]) async {
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            for location in locations {
                let creds = apiService.credentialsBody(from: devices, filterTo: location.deviceIds)
                guard !creds.isEmpty,
                      let first = devices.first(where: { location.deviceIds.contains($0.deviceId) }) else { continue }
                let signing = (first.deviceId, first.password)

                group.addTask { [weak self] in
                    await self?.refreshStatus(for: location.id, credentials: creds, signingDevice: signing)
                }
            }
        }
    }

    /// Clear status for a location (e.g. after disconnect)
    func clearStatus(for locationId: String) {
        statusMap.removeValue(forKey: locationId)
    }

    /// Clear all cached statuses
    func clearAll() {
        statusMap.removeAll()
    }
}
