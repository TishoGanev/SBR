//
//  WatchProtocol.swift
//  Shared by the iPhone app and the Watch app.
//

import Foundation

/// Tracking snapshot the phone pushes to the watch. Raw SI values; the watch formats them.
nonisolated struct WatchState: Codable, Equatable {
    var isTracking = false
    var isPaused = false
    var elapsed: TimeInterval = 0
    var distance: Double = 0       // metres
    var speed: Double = 0          // m/s
    var maxSpeed: Double = 0       // m/s
    var altitude: Double?          // metres
    var metric = true
    var sentAt = Date()

    static let messageKey = "state"

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.messageKey: data]
    }

    init() {}

    init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.messageKey] as? Data,
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = state
    }
}

/// Control the watch sends to the phone.
nonisolated enum WatchCommand: String {
    case start, pause, resume, stop

    static let messageKey = "command"

    var dictionary: [String: Any] { [Self.messageKey: rawValue] }

    init?(dictionary: [String: Any]) {
        guard let raw = dictionary[Self.messageKey] as? String, let command = Self(rawValue: raw) else { return nil }
        self = command
    }
}
