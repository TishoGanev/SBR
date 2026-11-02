//
//  MotionActivity.swift
//  Snowoboarders
//

import Foundation
import CoreMotion

enum MotionKind: String {
    case automotive, walking, cycling, stationary, unknown
}

struct MotionSample: Equatable {
    var kind: MotionKind
    /// CMMotionActivityConfidence raw value: 0 low, 1 medium, 2 high.
    var confidence: Int

    init(kind: MotionKind, confidence: Int) {
        self.kind = kind
        self.confidence = confidence
    }

    init(_ activity: CMMotionActivity) {
        let kind: MotionKind
        if activity.automotive { kind = .automotive }
        else if activity.cycling { kind = .cycling }
        else if activity.walking || activity.running { kind = .walking }
        else if activity.stationary { kind = .stationary }
        else { kind = .unknown }
        self.init(kind: kind, confidence: activity.confidence.rawValue)
    }
}

/// Settings keys for starting and stopping a recording from motion activity. Both default to off:
/// on a mountain a lift ride or a walk to the slope looks like walking or standing, and would stop a ride.
enum AutoRecordSettings {
    static let autoStartKey = "autoStartOnDriving"
    static let autoStopKey = "autoStopWhenIdle"
    static let stopMinutesKey = "autoStopMinutes"
    static let defaultStopMinutes = 3

    static var autoStart: Bool { UserDefaults.standard.bool(forKey: autoStartKey) }
    static var autoStop: Bool { UserDefaults.standard.bool(forKey: autoStopKey) }
    static var stopAfter: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: stopMinutesKey) as? Int ?? defaultStopMinutes
        return TimeInterval(max(minutes, 1)) * 60
    }
}

/// Decides when motion activity should start or stop a recording. The recorded points are never touched;
/// stopping only ends the session.
struct MotionAutoControl {
    enum Action: Equatable { case none, start, stop }

    var autoStart: Bool
    var autoStop: Bool
    var stopAfter: TimeInterval
    private var idleSince: Date?

    init(autoStart: Bool = false, autoStop: Bool = false, stopAfter: TimeInterval = 180) {
        self.autoStart = autoStart
        self.autoStop = autoStop
        self.stopAfter = stopAfter
    }

    /// Call on every activity change and on a timer: CoreMotion only reports changes, so "still idle
    /// after 3 minutes" has to be noticed by the clock.
    mutating func evaluate(_ sample: MotionSample?, now: Date, isTracking: Bool) -> Action {
        guard let sample else { return .none }
        if !isTracking {
            idleSince = nil
            return autoStart && sample.kind == .automotive && sample.confidence >= 1 ? .start : .none
        }
        guard autoStop else { idleSince = nil; return .none }
        switch sample.kind {
        case .stationary, .walking:
            let since = idleSince ?? now
            idleSince = since
            if now.timeIntervalSince(since) >= stopAfter {
                idleSince = nil
                return .stop
            }
        case .automotive, .cycling, .unknown:
            idleSince = nil
        }
        return .none
    }

    mutating func reset() { idleSince = nil }
}

/// Streams CoreMotion activity. Does nothing where motion data is unavailable or not permitted.
@MainActor
final class MotionActivityMonitor {
    private let manager = CMMotionActivityManager()
    private(set) var latest: MotionSample?
    var onChange: ((MotionSample) -> Void)?

    private var isRunning = false

    func start() {
        guard !isRunning, CMMotionActivityManager.isActivityAvailable() else { return }
        isRunning = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let sample = MotionSample(activity)
                self.latest = sample
                self.onChange?(sample)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        latest = nil
        manager.stopActivityUpdates()
    }
}
