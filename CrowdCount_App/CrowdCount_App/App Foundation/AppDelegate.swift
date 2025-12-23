import SwiftUI
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @AppStorage("selectedShortcutItem") var selectedShortcutItem: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Clear badge on launch
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error { print("Failed to clear badge: \(error.localizedDescription)") }
        }

        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        selectedShortcutItem = shortcutItem.type
        completionHandler(true)
    }

    // MARK: - Push Notification Registration

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Device Token: \(tokenString)")

        // Store token locally
        UserDefaults.standard.set(tokenString, forKey: "deviceToken")

        // Send token to server
        sendDeviceTokenToServer(token: tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Handle Incoming Notifications

    // Foreground notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // User tapped on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        // Handle ad approval notification
        if let type = userInfo["type"] as? String, type == "ad_approved" {
            if let adId = userInfo["ad_id"] as? String {
                // Post notification to navigate to ad details
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToAdDetails"),
                    object: nil,
                    userInfo: ["ad_id": adId]
                )
            }
        }

        completionHandler()
    }

    // MARK: - Server Communication

    private func sendDeviceTokenToServer(token: String) {
        guard let appId = UserDefaults.standard.string(forKey: "appId") else {
            print("No appId found, cannot register device token")
            return
        }

        guard let url = URL(string: "\(AppSettings.apiBaseURL)/update-device-token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app_id": appId,
            "device_token": token
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to send device token: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Device token registered successfully")
            }
        }.resume()
    }
}

