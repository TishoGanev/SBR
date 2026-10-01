//
//  LocationTracker.swift
//  Snowoboarders
//

import Foundation
import CoreLocation
import SwiftData
import Combine

@MainActor
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var traveledDistance: CLLocationDistance = 0
    @Published private(set) var maxSpeed: CLLocationSpeed = 0
    @Published private(set) var trackCoordinates: [CLLocationCoordinate2D] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var hasFixedLocation = false
    @Published private(set) var isPaused = false

    private(set) var startTime: Date?
    private(set) var startAltitude: Double?
    @Published private(set) var lastSessionId: Int?
    private var session: Int = 0
    private var lastLocation: CLLocation?
    private let manager = CLLocationManager()
    private var modelContext: ModelContext?
    private var durationTimer: Timer?
    private var segmentStart: Date?
    private var accumulatedBeforePause: TimeInterval = 0

    private static let accuracyThreshold: CLLocationDistance = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        startUpdatingIfAuthorized()
    }

    func configure(context: ModelContext) {
        self.modelContext = context
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    private func startUpdatingIfAuthorized() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startTracking() {
        guard !isTracking else { return }
        session = nextSessionId()
        startTime = Date()
        startAltitude = currentLocation?.altitude
        lastLocation = nil
        traveledDistance = 0
        maxSpeed = 0
        trackCoordinates = []
        elapsed = 0
        accumulatedBeforePause = 0
        isTracking = true
        isPaused = false
        manager.desiredAccuracy = kCLLocationAccuracyBest

        startTimer()
    }

    func pauseTracking() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        accumulatedBeforePause = currentSegmentElapsed()
        segmentStart = nil
        elapsed = accumulatedBeforePause
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func resumeTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        lastLocation = nil
        startTimer()
    }

    private func currentSegmentElapsed() -> TimeInterval {
        accumulatedBeforePause + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startTimer() {
        segmentStart = Date()
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = self.currentSegmentElapsed()
            }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        isPaused = false
        lastSessionId = session
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        segmentStart = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func discardLastSession() {
        guard let context = modelContext, let sessionId = lastSessionId else { return }
        let descriptor = FetchDescriptor<TrackPoint>(predicate: #Predicate { $0.session == sessionId })
        if let points = try? context.fetch(descriptor) {
            for point in points { context.delete(point) }
            try? context.save()
        }
        lastSessionId = nil
    }

    private func nextSessionId() -> Int {
        guard let context = modelContext else { return 1 }
        let descriptor = FetchDescriptor<TrackPoint>(sortBy: [SortDescriptor(\.session, order: .reverse)])
        let maxSession = (try? context.fetch(descriptor))?.first?.session ?? 0
        return maxSession + 1
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.startUpdatingIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location: location)
        }
    }

    /// CLLocation.speed is -1 when the device can't compute a valid speed; clamp it to 0.
    var currentSpeed: CLLocationSpeed { max(0, currentLocation?.speed ?? 0) }

    private func handle(location: CLLocation) {
        currentLocation = location
        hasFixedLocation = true
        guard isTracking, !isPaused else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < Self.accuracyThreshold else { return }

        if let last = lastLocation {
            traveledDistance += location.distance(from: last)
        }
        lastLocation = location
        maxSpeed = max(maxSpeed, location.speed)
        trackCoordinates.append(location.coordinate)

        if let context = modelContext {
            let point = TrackPoint(location: location, session: session)
            context.insert(point)
            try? context.save()
        }
    }
}
