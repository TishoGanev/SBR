//
//  RideActivityController.swift
//  Snowoboarders
//

import ActivityKit
import Foundation

/// Mirrors the tracked ride onto the Lock Screen and Dynamic Island.
@MainActor
final class RideActivityController {
    // `Activity` alone is the app's run/lift/still enum.
    private var activity: ActivityKit.Activity<RideActivityAttributes>?
    private var lastSent: RideActivityAttributes.ContentState?
    private var lastSentAt: Date = .distantPast

    /// Location fixes arrive about once a second; the banner only needs a fresh speed every few seconds.
    private static let minInterval: TimeInterval = 4

    init() {
        // A ride the app was killed during leaves its activity behind; nothing will update it again.
        for stale in ActivityKit.Activity<RideActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// iOS only lets an app start a Live Activity while it is in the foreground. A ride started from the
    /// watch reaches a phone that is usually locked, so that first request fails; `update` tries again
    /// on every location fix until the app is opened, and the activity then appears with the ride's real time.
    func start(_ state: RideActivityAttributes.ContentState) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let metric = UserDefaults.standard.object(forKey: "unitsMetric") as? Bool ?? true
        do {
            activity = try ActivityKit.Activity.request(
                attributes: RideActivityAttributes(metric: metric),
                content: ActivityContent(state: state, staleDate: nil)
            )
            lastSent = state
            lastSentAt = Date()
        } catch {
            activity = nil
        }
    }

    /// Pass `force` for changes the rider should see at once, like pausing or a new activity.
    func update(_ state: RideActivityAttributes.ContentState, force: Bool = false) {
        guard let activity else {
            start(state)
            return
        }
        guard state != lastSent else { return }
        let changedMode = state.motion != lastSent?.motion || state.pausedElapsed != lastSent?.pausedElapsed
        guard force || changedMode || Date().timeIntervalSince(lastSentAt) >= Self.minInterval else { return }
        lastSent = state
        lastSentAt = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(_ state: RideActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        lastSent = nil
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default) }
    }
}
