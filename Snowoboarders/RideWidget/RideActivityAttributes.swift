//
//  RideActivityAttributes.swift
//  Snowoboarders
//
//  Shared by the app, which starts and updates the Live Activity, and RideWidget, which draws it.
//

import ActivityKit
import Foundation

// The app target defaults to MainActor isolation; ActivityKit uses these types off the main actor.
nonisolated struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Motion: String, Codable, Hashable {
            case run, lift, still
        }

        /// Metres per second.
        var speed: Double
        var maxSpeed: Double
        /// Metres.
        var distance: Double
        var motion: Motion
        /// The ride timer reads `now - timerStart`, so the system can tick it without updates from the app.
        var timerStart: Date
        /// Frozen elapsed time while paused; nil while the timer runs.
        var pausedElapsed: TimeInterval?
    }

    var metric: Bool
}
