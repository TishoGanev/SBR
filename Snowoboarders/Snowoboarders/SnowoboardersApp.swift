//
//  SnowoboardersApp.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData

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
