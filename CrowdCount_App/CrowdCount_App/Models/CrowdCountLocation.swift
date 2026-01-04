import Foundation
import CoreLocation
import SwiftUI

/// Represents a location with one or more counter devices.
/// This is the primary entity in the location-centric model.
struct CrowdCountLocation: Identifiable, Codable, Equatable {
    /// Unique identifier (primary device ID for server-defined locations, UUID string for local virtual locations)
    let id: String

    /// Display name for the location
    var name: String

    /// Optional address
    var address: String?

    /// Geographic coordinate (nil for unmapped/virtual locations)
    var latitude: Double?
    var longitude: Double?

    /// Display properties
    var color: String?
    var icon: String?

    /// Comparison trend from server
    var comparison: String

    /// The counters belonging to this location
    var counters: [Counter]

    /// Whether this is a server-defined location (on map) or a local virtual location
    var isOnMap: Bool

    // MARK: - Computed Properties

    /// Aggregated count from all counters
    var currentCount: Int {
        counters.reduce(0) { $0 + $1.currentCount }
    }

    /// Aggregated overcrowding limit (sum of all counter limits that are set)
    var overcrowdingLimit: Int? {
        let limits = counters.compactMap { $0.overcrowdingLimit }
        return limits.isEmpty ? nil : limits.reduce(0, +)
    }

    /// Coordinate if location is on map
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Whether any counter in this location has a negative count
    var hasNegativeCounter: Bool {
        counters.contains { $0.isNegative }
    }

    /// Number of counters in this location
    var counterCount: Int {
        counters.count
    }

    /// Whether this is a single-counter location
    var isSingleCounter: Bool {
        counters.count == 1
    }

    /// Subtitle text for display (e.g., "3 counters" or "1 counter")
    var counterSubtitle: String {
        counterCount == 1 ? "1 counter" : "\(counterCount) counters"
    }

    /// Overall connection status (online if all online, partial if mixed, offline if all offline)
    var connectionStatus: LocationConnectionStatus {
        let statuses = counters.map { $0.connectionStatus }
        let onlineCount = statuses.filter { $0 == .online }.count
        let offlineCount = statuses.filter { $0 == .offline }.count

        if onlineCount == counters.count {
            return .allOnline
        } else if offlineCount == counters.count {
            return .allOffline
        } else if onlineCount > 0 {
            return .partial
        } else {
            return .unknown
        }
    }

    /// Comparison symbol for display
    var comparisonSymbol: String {
        switch comparison {
        case "up": return "↑"
        case "down": return "↓"
        default: return ""
        }
    }

    /// Comparison color for display
    var comparisonColor: Color {
        switch comparison {
        case "up": return .red
        case "down": return .green
        default: return .primary
        }
    }

    /// Display color (defaults to blue)
    var displayColor: Color {
        Color.fromString(color ?? "blue")
    }

    /// Display icon (defaults to building.2)
    var displayIcon: String {
        icon ?? "building.2"
    }

    enum LocationConnectionStatus {
        case allOnline
        case allOffline
        case partial
        case unknown
    }

    // MARK: - Initializers

    init(id: String, name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil, color: String? = nil, icon: String? = nil, comparison: String = "neutral", counters: [Counter] = [], isOnMap: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.color = color
        self.icon = icon
        self.comparison = comparison
        self.counters = counters
        self.isOnMap = isOnMap
    }

    /// Create a virtual (local-only) single-counter location
    static func virtualLocation(for counter: Counter) -> CrowdCountLocation {
        CrowdCountLocation(
            id: counter.deviceId,
            name: counter.label,
            comparison: "neutral",
            counters: [counter],
            isOnMap: false
        )
    }
}

// MARK: - Hashable

extension CrowdCountLocation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Note: Color.fromString is defined in Map/Color.swift
