//
//  PhoneWatchBridge.swift
//  Snowoboarders
//

import Foundation
import Combine
import CoreLocation
import WatchConnectivity

/// Mirrors the tracker to the paired Apple Watch and applies start/pause/stop commands from it.
@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    private weak var tracker: LocationTracker?
    private var cancellables = Set<AnyCancellable>()
    private var lastSent = WatchState()
    private var lastSentAt = Date.distantPast

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start(tracker: LocationTracker) {
        guard self.tracker == nil, let session else { return }
        self.tracker = tracker
        session.delegate = self
        session.activate()

        // Elapsed time ticks every second, so this also acts as the update heartbeat.
        tracker.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.push() }
            .store(in: &cancellables)
    }

    private func currentState() -> WatchState {
        var state = WatchState()
        guard let tracker else { return state }
        state.isTracking = tracker.isTracking
        state.isPaused = tracker.isPaused
        state.elapsed = tracker.elapsed
        state.distance = tracker.traveledDistance
        state.speed = tracker.isPaused ? 0 : tracker.currentSpeed
        state.maxSpeed = tracker.maxSpeed
        state.altitude = tracker.currentLocation?.altitude
        state.metric = UserDefaults.standard.object(forKey: "unitsMetric") as? Bool ?? true
        return state
    }

    private func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let state = currentState()
        let modeChanged = state.isTracking != lastSent.isTracking || state.isPaused != lastSent.isPaused
        guard modeChanged || Date().timeIntervalSince(lastSentAt) >= 1 else { return }
        lastSent = state
        lastSentAt = Date()

        if session.isReachable {
            session.sendMessage(state.dictionary, replyHandler: nil, errorHandler: nil)
        }
        // The latest context also reaches a watch app that launches later.
        if modeChanged || !state.isTracking {
            try? session.updateApplicationContext(state.dictionary)
        }
    }

    private func apply(_ command: WatchCommand) {
        guard let tracker else { return }
        switch command {
        case .start: tracker.startTracking()
        case .pause: tracker.pauseTracking()
        case .resume: tracker.resumeTracking()
        case .stop: tracker.stopTracking()
        }
        lastSentAt = .distantPast
        push()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.lastSentAt = .distantPast; self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSentAt = .distantPast; self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchCommand(dictionary: message) else { return }
        Task { @MainActor in self.apply(command) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let command = WatchCommand(dictionary: message) {
            Task { @MainActor in self.apply(command) }
        }
        replyHandler([:])
    }
}
