import SwiftUI

class AppDelegate: UIResponder, UIApplicationDelegate {
    @AppStorage("selectedShortcutItem") var selectedShortcutItem: String?

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        selectedShortcutItem = shortcutItem.type
        completionHandler(true)
    }
}
