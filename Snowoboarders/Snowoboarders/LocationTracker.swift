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
    /// What the rider is doing right now; standing still adds nothing to distance or the track.
    @Published private(set) var activity: Activity = .still
    private var classifier = LiveActivityClassifier()

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
    private let liveActivity = RideActivityController()

    /// Fixes less accurate than this are not recorded. Stricter than the 50 m used as the default in
    /// `FixFilter`, which is only a fallback.
    private static let accuracyThreshold: CLLocationDistance = 20

    private var fixFilter = FixFilter(maxHorizontalAccuracy: LocationTracker.accuracyThreshold)
    private let motion = MotionActivityMonitor()
    private var autoControl = MotionAutoControl()

    override init() {
        super.init()
        manager.delegate = self
        // Update rate is left to the system on purpose: no distanceFilter, no auto-pausing and
        // `.other`, with Best accuracy while recording. Fixes can still come every 6-12 s when the
        // device is standing still; that is iOS saving power and is separate from timestamp precision.
        manager.activityType = .other
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        motion.onChange = { [weak self] sample in self?.applyMotion(sample) }
        refreshMotionMonitoring()
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
        fixFilter = FixFilter(maxHorizontalAccuracy: Self.accuracyThreshold, notBefore: startTime)
        autoControl.reset()
        traveledDistance = 0
        maxSpeed = 0
        trackCoordinates = []
        elapsed = 0
        accumulatedBeforePause = 0
        classifier.reset()
        activity = .still
        isTracking = true
        isPaused = false
        manager.desiredAccuracy = kCLLocationAccuracyBest
        refreshMotionMonitoring()

        startTimer()
        liveActivity.start(liveActivityState)
    }

    func pauseTracking() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        accumulatedBeforePause = currentSegmentElapsed()
        segmentStart = nil
        elapsed = accumulatedBeforePause
        durationTimer?.invalidate()
        durationTimer = nil
        liveActivity.update(liveActivityState, force: true)
    }

    func resumeTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        lastLocation = nil
        classifier.reset()
        activity = .still
        startTimer()
        liveActivity.update(liveActivityState, force: true)
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
                self.applyMotion(self.motion.latest)
            }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        isPaused = false
        // Before `segmentStart` is cleared, so the final banner keeps the ride's time.
        liveActivity.end(liveActivityState)
        lastSessionId = session
        fixFilter.metadata.save(session: session)
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        refreshMotionMonitoring()
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
        // iOS can deliver several fixes at once; dropping all but the last left gaps in the timeline.
        Task { @MainActor in
            for location in locations { self.handle(location: location) }
        }
    }

    private var liveActivityState: RideActivityAttributes.ContentState {
        let motion: RideActivityAttributes.ContentState.Motion = switch activity {
        case .run: .run
        case .lift: .lift
        case .still: .still
        }
        let running = currentSegmentElapsed()
        return RideActivityAttributes.ContentState(
            speed: activity == .still ? 0 : currentSpeed,
            maxSpeed: max(0, maxSpeed),
            distance: traveledDistance,
            motion: motion,
            timerStart: Date().addingTimeInterval(-running),
            pausedElapsed: isPaused || !isTracking ? running : nil
        )
    }

    /// CLLocation.speed is -1 when the device can't compute a valid speed; clamp it to 0.
    var currentSpeed: CLLocationSpeed { max(0, currentLocation?.speed ?? 0) }

    private func handle(location: CLLocation) {
        currentLocation = location
        hasFixedLocation = true
        guard isTracking, !isPaused else { return }
        guard fixFilter.check(location) == .accept else { return }

        classifier.add(location)
        activity = classifier.activity
        // While standing, GPS drift would add distance and speed from nothing. The point is still
        // stored below, so the ride keeps its timeline.
        if activity != .still {
            if let last = lastLocation {
                let step = location.distance(from: last)
                // Noise-sized steps are skipped and the anchor stays, so slow real movement still adds up.
                if DistanceRule.counts(displacement: step, speed: location.speed, accuracy: location.horizontalAccuracy) {
                    traveledDistance += step
                    lastLocation = location
                }
            } else {
                lastLocation = location
            }
            maxSpeed = max(maxSpeed, location.speed)
            trackCoordinates.append(location.coordinate)
        }
        liveActivity.update(liveActivityState)

        if let context = modelContext {
            let point = TrackPoint(location: location, session: session, motion: motion.latest)
            context.insert(point)
            try? context.save()
        }
    }

    // MARK: - Motion activity

    /// Motion data is only asked for while recording, or when auto-start needs it to notice driving.
    func refreshMotionMonitoring() {
        if isTracking || AutoRecordSettings.autoStart {
            motion.start()
        } else {
            motion.stop()
        }
    }

    private func applyMotion(_ sample: MotionSample?) {
        autoControl.autoStart = AutoRecordSettings.autoStart
        autoControl.autoStop = AutoRecordSettings.autoStop
        autoControl.stopAfter = AutoRecordSettings.stopAfter
        switch autoControl.evaluate(sample, now: Date(), isTracking: isTracking) {
        case .start: startTracking()
        case .stop: stopTracking()
        case .none: break
        }
    }
}
