import SwiftUI
import Combine

class AppSettings: ObservableObject {
    // MARK: - API Configuration
    static let apiBaseURL = "https://api.crowdcount.tech"
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

    // MARK: - Feature Flags

    /// When true, the app uses the location-centric UI model where locations are the primary entity
    /// and counters are nested within locations. When false, uses the legacy counter-centric model.
    @Published var useLocationCentricUI: Bool {
        didSet {
            UserDefaults.standard.set(useLocationCentricUI, forKey: "useLocationCentricUI")
        }
    }

    /// Whether the user has seen the explanation for negative counter values in multi-counter locations
    @Published var hasSeenNegativeCountExplanation: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenNegativeCountExplanation, forKey: "hasSeenNegativeCountExplanation")
        }
    }

    init() {
        // Dark mode preference
        if UserDefaults.standard.object(forKey: "isDarkMode") == nil {
            self.isDarkMode = true // Default to dark mode
            UserDefaults.standard.set(true, forKey: "isDarkMode")
        } else {
            self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        }

        // Location-centric UI feature flag (default: enabled for new installs)
        if UserDefaults.standard.object(forKey: "useLocationCentricUI") == nil {
            self.useLocationCentricUI = true // Default to new location-centric UI
            UserDefaults.standard.set(true, forKey: "useLocationCentricUI")
        } else {
            self.useLocationCentricUI = UserDefaults.standard.bool(forKey: "useLocationCentricUI")
        }

        // Negative count explanation flag
        self.hasSeenNegativeCountExplanation = UserDefaults.standard.bool(forKey: "hasSeenNegativeCountExplanation")
    }
}
