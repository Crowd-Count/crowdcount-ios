import Foundation
import SwiftUI

/// Manages device nicknames across the app using UserDefaults
class NicknameManager: ObservableObject {
    static let shared = NicknameManager()

    /// Published nicknames dictionary: [deviceId: nickname]
    @Published private(set) var nicknames: [String: String] = [:]

    private init() {
        loadFromLocal()
    }

    // MARK: - Public Methods

    /// Get nickname for a device (returns empty string if no nickname set)
    func nickname(for deviceId: String) -> String {
        nicknames[deviceId] ?? ""
    }

    /// Get display name for a device (nickname if set, otherwise device ID)
    func displayName(for deviceId: String) -> String {
        let nick = nicknames[deviceId] ?? ""
        return nick.isEmpty ? deviceId : nick
    }

    /// Set nickname for a device
    func setNickname(_ nickname: String, for deviceId: String) {
        if nickname.isEmpty {
            nicknames.removeValue(forKey: deviceId)
        } else {
            nicknames[deviceId] = nickname
        }
        saveToLocal()
    }

    // MARK: - Private Methods

    private func loadFromLocal() {
        if let data = UserDefaults.standard.data(forKey: "deviceNicknames"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            nicknames = decoded
        }
    }

    private func saveToLocal() {
        if let data = try? JSONEncoder().encode(nicknames) {
            UserDefaults.standard.set(data, forKey: "deviceNicknames")
        }
    }
}
