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

    private(set) var startTime: Date?
    private var session: Int = 0
    private var lastLocation: CLLocation?
    private let manager = CLLocationManager()
    private var modelContext: ModelContext?
    private var durationTimer: Timer?

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
        lastLocation = nil
        traveledDistance = 0
        maxSpeed = 0
        trackCoordinates = []
        elapsed = 0
        isTracking = true
        manager.desiredAccuracy = kCLLocationAccuracyBest

        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let startTime = self.startTime else { return }
            self.elapsed = Date().timeIntervalSince(startTime)
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        durationTimer?.invalidate()
        durationTimer = nil
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

    private func handle(location: CLLocation) {
        currentLocation = location
        hasFixedLocation = true
        guard isTracking else { return }
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
