//
//  VigilantRemoteApp.swift
//  Vigilant Remote (iOS)
//

import SwiftUI
import UIKit

@main
struct VigilantRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = RemoteModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.refresh()
                        model.startPolling()
                    case .background, .inactive:
                        model.stopPolling()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            RemoteModel.shared.handleRemoteChange()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Vigilant Remote: push registration failed: \(error.localizedDescription)")
    }
}
