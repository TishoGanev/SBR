//
//  WatchLink.swift
//  SnowoboardersWatch
//

import Foundation
import WatchConnectivity

/// Receives live tracking state from the phone and sends it start/pause/stop commands.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var state = WatchState()
    @Published private(set) var isReachable = false
    private var receivedAt = Date()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Elapsed time at `date`, running locally between phone updates while recording.
    func elapsed(at date: Date) -> TimeInterval {
        guard state.isTracking, !state.isPaused else { return state.elapsed }
        return state.elapsed + max(0, date.timeIntervalSince(receivedAt))
    }

    func send(_ command: WatchCommand) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(command.dictionary, replyHandler: nil, errorHandler: nil)
    }

    private func receive(_ dictionary: [String: Any]) {
        guard let newState = WatchState(dictionary: dictionary) else { return }
        DispatchQueue.main.async {
            self.state = newState
            self.receivedAt = Date()
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
        receive(session.receivedApplicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }
}
