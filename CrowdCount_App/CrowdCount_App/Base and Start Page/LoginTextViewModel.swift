import SwiftUI

class LoginTextViewModel: ObservableObject {
    @Published var loginText: String = "Tap me!"  // Default fallback
    @Published var isLoading: Bool = false

    private let userDefaultsKey = "cachedLoginText"

    init() {
        // Load cached text immediately (shown until fetch completes)
        if let cached = UserDefaults.standard.string(forKey: userDefaultsKey) {
            loginText = cached
        }
    }

    func fetchLoginText() {
        guard let url = URL(string: "\(AppSettings.apiBaseURL)/login-text") else {
            print("[LoginText] Invalid URL")
            return
        }

        isLoading = true

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    print("[LoginText] Error fetching: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    print("[LoginText] No data received")
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let text = json["text"] as? String {
                        self?.loginText = text
                        // Cache for offline fallback
                        UserDefaults.standard.set(text, forKey: self?.userDefaultsKey ?? "")
                        print("[LoginText] Updated: \(text)")
                    }
                } catch {
                    print("[LoginText] Error parsing JSON: \(error)")
                }
            }
        }.resume()
    }
}
