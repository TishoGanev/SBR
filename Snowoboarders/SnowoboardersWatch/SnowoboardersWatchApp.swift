//
//  SnowoboardersWatchApp.swift
//  SnowoboardersWatch
//

import SwiftUI

@main
struct SnowoboardersWatchApp: App {
    @StateObject private var link = WatchLink()
    @StateObject private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchTrackView()
                .environmentObject(link)
                .environmentObject(workout)
        }
    }
}
