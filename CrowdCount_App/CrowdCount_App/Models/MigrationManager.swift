import Foundation

/// Manages migration from the legacy counter-centric model to the new location-centric model.
/// This is a backwards-compatible migration that preserves all existing data.
@MainActor
class MigrationManager: ObservableObject {
    static let shared = MigrationManager()

    private let apiService = APIService.shared

    /// Keys for UserDefaults storage
    private enum Keys {
        static let migrationCompleted = "migrationCompleted_v2"
        static let legacyUsers = "users"
        static let legacyUserPasswords = "userPasswords"
        static let locations = "crowdcount_locations"
        static let counterPasswords = "crowdcount_counter_passwords"
    }

    /// Whether the migration has already been completed
    var isMigrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: Keys.migrationCompleted)
    }

    /// Load locations from UserDefaults (new model)
    func loadLocations() -> [CrowdCountLocation] {
        guard let data = UserDefaults.standard.data(forKey: Keys.locations),
              let locations = try? JSONDecoder().decode([CrowdCountLocation].self, from: data) else {
            return []
        }
        return locations
    }

    /// Save locations to UserDefaults (new model)
    func saveLocations(_ locations: [CrowdCountLocation]) {
        if let data = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(data, forKey: Keys.locations)
        }
    }

    /// Load counter passwords from UserDefaults (new model)
    func loadCounterPasswords() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Keys.counterPasswords),
              let passwords = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return passwords
    }

    /// Save counter passwords to UserDefaults (new model)
    func saveCounterPasswords(_ passwords: [String: String]) {
        if let data = try? JSONEncoder().encode(passwords) {
            UserDefaults.standard.set(data, forKey: Keys.counterPasswords)
        }
    }

    /// Perform the migration from legacy User model to new CrowdCountLocation model.
    /// This is safe to call multiple times - it will only migrate once.
    func performMigrationIfNeeded() async -> [CrowdCountLocation] {
        // If already migrated, just load existing locations
        if isMigrationCompleted {
            return loadLocations()
        }

        // Load legacy data
        let legacyUsers = loadLegacyUsers()

        // If no legacy users, just mark migration as complete
        if legacyUsers.isEmpty {
            UserDefaults.standard.set(true, forKey: Keys.migrationCompleted)
            return []
        }

        // Perform migration
        let locations = await migrateUsers(legacyUsers)

        // Migrate passwords
        migratePasswords()

        // Save migrated locations
        saveLocations(locations)

        // Mark migration as complete (but keep legacy data for rollback)
        UserDefaults.standard.set(true, forKey: Keys.migrationCompleted)

        return locations
    }

    /// Force a re-migration (for debugging/rollback scenarios)
    func forceMigration() async -> [CrowdCountLocation] {
        UserDefaults.standard.set(false, forKey: Keys.migrationCompleted)
        return await performMigrationIfNeeded()
    }

    // MARK: - Private Methods

    /// Load legacy users from UserDefaults
    private func loadLegacyUsers() -> [LegacyUser] {
        guard let data = UserDefaults.standard.data(forKey: Keys.legacyUsers),
              let users = try? JSONDecoder().decode([LegacyUser].self, from: data) else {
            return []
        }
        return users
    }

    /// Load legacy passwords from UserDefaults
    private func loadLegacyPasswords() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: Keys.legacyUserPasswords),
              let passwords = try? JSONDecoder().decode([UUID: String].self, from: data) else {
            return [:]
        }
        return passwords
    }

    /// Migrate passwords from UUID-keyed to deviceId-keyed format
    private func migratePasswords() {
        let legacyUsers = loadLegacyUsers()
        let legacyPasswords = loadLegacyPasswords()

        var newPasswords: [String: String] = [:]
        for user in legacyUsers {
            if let password = legacyPasswords[user.id] {
                newPasswords[user.userId] = password
            }
        }

        saveCounterPasswords(newPasswords)
    }

    /// Migrate legacy users to locations by querying server for map status
    private func migrateUsers(_ users: [LegacyUser]) async -> [CrowdCountLocation] {
        // Query server for each device's map status
        let deviceIds = users.map { $0.userId }
        let mapStatuses = await apiService.fetchAllDeviceMapStatuses(deviceIds: deviceIds)

        // Group devices by their primary device (location)
        var locationGroups: [String: [(LegacyUser, APIService.DeviceMapStatus?)]] = [:]

        for user in users {
            let status = mapStatuses[user.userId]

            if let status = status, status.on_map, let primaryDevice = status.primary_device {
                // This device is on the map - group by primary device
                locationGroups[primaryDevice, default: []].append((user, status))
            } else {
                // This device is not on the map - create its own virtual location
                locationGroups[user.userId, default: []].append((user, nil))
            }
        }

        // Fetch server location data for enrichment
        let serverLocations = (try? await apiService.fetchAllLocationData()) ?? []
        let serverLocationMap = Dictionary(uniqueKeysWithValues: serverLocations.map { ($0.location_device, $0) })

        // Build CrowdCountLocation for each group
        var locations: [CrowdCountLocation] = []

        for (primaryDeviceId, group) in locationGroups {
            let serverData = serverLocationMap[primaryDeviceId]
            let isOnMap = serverData != nil

            // Determine location name
            let locationName: String
            if let serverName = serverData?.location_name {
                locationName = serverName
            } else if let firstStatus = group.first?.1, let name = firstStatus.location_name {
                locationName = name
            } else {
                // Use device name or ID for virtual locations
                let deviceName = loadDeviceName(for: primaryDeviceId)
                locationName = deviceName ?? primaryDeviceId
            }

            // Build counters from group
            var counters: [Counter] = []

            if let serverData = serverData, let breakdown = serverData.device_breakdown, !breakdown.isEmpty {
                // Use server's device breakdown for multi-counter locations
                for device in breakdown {
                    counters.append(Counter(
                        deviceId: device.device_id,
                        label: device.device_label,
                        currentCount: device.count,
                        overcrowdingLimit: device.overcrowding.intValue,
                        connectionStatus: .unknown
                    ))
                }
            } else {
                // Single device or no breakdown - use legacy user data
                for (user, _) in group {
                    let deviceName = loadDeviceName(for: user.userId)

                    counters.append(Counter(
                        deviceId: user.userId,
                        label: deviceName ?? user.userId,
                        currentCount: user.currentCount,
                        overcrowdingLimit: user.overcrowdingLimit,
                        connectionStatus: .unknown
                    ))
                }
            }

            let location = CrowdCountLocation(
                id: primaryDeviceId,
                name: locationName,
                address: serverData?.location_address,
                latitude: serverData?.location_latitude,
                longitude: serverData?.location_longitude,
                color: serverData?.location_color,
                icon: serverData?.location_icon,
                comparison: serverData?.location_comparison ?? "neutral",
                counters: counters,
                isOnMap: isOnMap
            )

            locations.append(location)
        }

        return locations.sorted { $0.name < $1.name }
    }

    /// Load custom device name from UserDefaults
    private func loadDeviceName(for deviceId: String) -> String? {
        UserDefaults.standard.string(forKey: "deviceName_\(deviceId)")
    }

    // MARK: - Add New Counter

    /// Add a new counter device, grouping it with existing location if on map
    func addCounter(deviceId: String, password: String) async -> CrowdCountLocation? {
        // Check if device is on map
        let mapStatus = try? await apiService.getDeviceMapStatus(deviceId: deviceId)

        var locations = loadLocations()
        var passwords = loadCounterPasswords()

        // Save password
        passwords[deviceId] = password
        saveCounterPasswords(passwords)

        let newCounter = Counter(
            deviceId: deviceId,
            label: loadDeviceName(for: deviceId) ?? deviceId,
            currentCount: 0,
            overcrowdingLimit: nil,
            connectionStatus: .unknown
        )

        if let status = mapStatus, status.on_map, let primaryDevice = status.primary_device {
            // Device is on map - find or create location
            if let index = locations.firstIndex(where: { $0.id == primaryDevice }) {
                // Add to existing location if not already there
                if !locations[index].counters.contains(where: { $0.deviceId == deviceId }) {
                    locations[index].counters.append(newCounter)
                }
                saveLocations(locations)
                return locations[index]
            } else {
                // Fetch location data from server
                if let serverLocations = try? await apiService.fetchAllLocationData(),
                   let serverData = serverLocations.first(where: { $0.location_device == primaryDevice }) {

                    var counters: [Counter] = []
                    if let breakdown = serverData.device_breakdown, !breakdown.isEmpty {
                        counters = breakdown.map { device in
                            Counter(
                                deviceId: device.device_id,
                                label: device.device_label,
                                currentCount: device.count,
                                overcrowdingLimit: device.overcrowding.intValue,
                                connectionStatus: .unknown
                            )
                        }
                    } else {
                        counters = [newCounter]
                    }

                    let newLocation = CrowdCountLocation(
                        id: primaryDevice,
                        name: serverData.location_name,
                        address: serverData.location_address,
                        latitude: serverData.location_latitude,
                        longitude: serverData.location_longitude,
                        color: serverData.location_color,
                        icon: serverData.location_icon,
                        comparison: serverData.location_comparison,
                        counters: counters,
                        isOnMap: true
                    )
                    locations.append(newLocation)
                    saveLocations(locations)
                    return newLocation
                }
            }
        }

        // Device not on map - create virtual single-counter location
        let virtualLocation = CrowdCountLocation.virtualLocation(for: newCounter)
        locations.append(virtualLocation)
        saveLocations(locations)
        return virtualLocation
    }

    /// Remove a counter and its location if it's the last counter
    func removeCounter(deviceId: String) {
        var locations = loadLocations()
        var passwords = loadCounterPasswords()

        // Remove password
        passwords.removeValue(forKey: deviceId)
        saveCounterPasswords(passwords)

        // Find and update location
        for i in locations.indices {
            if let counterIndex = locations[i].counters.firstIndex(where: { $0.deviceId == deviceId }) {
                locations[i].counters.remove(at: counterIndex)

                // Remove location if no more counters
                if locations[i].counters.isEmpty {
                    locations.remove(at: i)
                    break
                }
            }
        }

        saveLocations(locations)
    }
}

// MARK: - Legacy User Model (for migration)

private struct LegacyUser: Identifiable, Codable {
    let id: UUID
    let userId: String
    var currentCount: Int
    var overcrowdingLimit: Int?
}
