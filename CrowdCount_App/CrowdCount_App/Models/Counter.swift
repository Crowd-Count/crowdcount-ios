import Foundation

/// Represents an individual counter device within a location.
/// Replaces the concept of `User` in the old counter-centric model.
struct Counter: Identifiable, Codable, Equatable {
    let deviceId: String
    var label: String
    var currentCount: Int
    var overcrowdingLimit: Int?

    /// Connection status of the counter device
    var connectionStatus: ConnectionStatus = .unknown

    /// id is derived from deviceId - ensures same device always has same id
    var id: String { deviceId }

    /// Whether this counter's count is negative (expected in multi-counter locations)
    var isNegative: Bool {
        currentCount < 0
    }

    enum ConnectionStatus: String, Codable {
        case online
        case offline
        case unknown
    }

    enum CodingKeys: String, CodingKey {
        case deviceId
        case label
        case currentCount
        case overcrowdingLimit
        case connectionStatus
    }

    init(deviceId: String, label: String, currentCount: Int = 0, overcrowdingLimit: Int? = nil, connectionStatus: ConnectionStatus = .unknown) {
        self.deviceId = deviceId
        self.label = label
        self.currentCount = currentCount
        self.overcrowdingLimit = overcrowdingLimit
        self.connectionStatus = connectionStatus
    }
}

// MARK: - Counter Hashable

extension Counter: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
