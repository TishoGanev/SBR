//
//  SnowoboardersApp.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData
import UIKit
import FBSDKCoreKit

@main
struct SnowoboardersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TrackPoint.self)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if AuthStore.isFacebookConfigured {
            ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        return true
    }
}
