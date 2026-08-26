//
//  VigilantApp.swift
//  Vigilant (macOS menu-bar agent)
//
//  Runs quietly in the menu bar on the Mac Mini. Registers for silent
//  push so it reacts instantly when the phone flips the switch, and
//  shows a small status/control panel.
//

import SwiftUI
import AppKit

@main
struct VigilantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = AppController.shared

    var body: some Scene {
        // A real, openable window (Dock icon + main window)…
        Window("Vigilant", id: "main") {
            RootView(controller: controller)
        }
        .windowResizability(.contentSize)

        // …plus the always-available menu-bar quick toggle.
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            Image(systemName: controller.isActive ? "eye.fill" : "eye")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: Dock icon + openable window, and the menu-bar icon.
        AppController.shared.start()

        // Register for silent CloudKit pushes.
        NSApplication.shared.registerForRemoteNotifications()
    }

    // Closing the window keeps the agent alive in the menu bar (background work
    // continues). Use ⌘Q or "Quit Vigilant" to actually exit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking the Dock icon reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit manages routing; nothing to send anywhere.
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Vigilant: remote notification registration failed: \(error.localizedDescription)")
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        // A CloudKit change arrived — pull the latest state and re-evaluate.
        AppController.shared.handleRemoteChange()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.stop()
    }
}
