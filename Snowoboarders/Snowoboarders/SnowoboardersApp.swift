//
//  SnowoboardersApp.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData

@main
struct SnowoboardersApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TrackPoint.self)
    }
}
