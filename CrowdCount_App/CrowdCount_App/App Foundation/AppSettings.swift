import SwiftUI
import Combine

class AppSettings: ObservableObject {
    // MARK: - API Configuration
    static let testing = false

    static let apiBaseURL: String = testing
        ? "https://api-staging.crowdcount.tech"
        : "https://api.crowdcount.tech"

    static let legacyAPIBaseURL = "https://crowdcount.tech/api"

    // Helper method for building endpoints
    static func apiEndpoint(_ path: String) -> String {
        // Remove leading slash if present to avoid double slashes
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "\(apiBaseURL)/\(cleanPath)"
    }

    // MARK: - User Preferences
    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: "isDarkMode") == nil {
            self.isDarkMode = true // Default to dark mode
            UserDefaults.standard.set(true, forKey: "isDarkMode")
        } else {
            self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        }
    }
}
