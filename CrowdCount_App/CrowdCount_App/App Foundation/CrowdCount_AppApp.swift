//
//  CrowdCount_AppApp.swift
//  CrowdCount_App
//
//  Created by Elkan Bruha on 6/11/24.
//

import SwiftUI
import Stripe

@main
struct CrowdCount_AppApp: App {
    @StateObject private var appSettings = AppSettings()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("selectedShortcutItem") private var selectedShortcutItem: String?

    init() {
        StripeConfig.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.isDarkMode ? .dark : .light)
                .onAppear {
                    if let shortcut = selectedShortcutItem {
                        handleShortcut(shortcut)
                        selectedShortcutItem = nil
                    }
                }
        }
    }

    private func handleShortcut(_ shortcut: String) {
        if shortcut == "com.CrowdCount.openmap" {
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToMap"), object: nil)
        }
    }
}
