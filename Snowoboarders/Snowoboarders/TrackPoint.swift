//
//  TrackPoint.swift
//  Snowoboarders
//

import Foundation
import CoreLocation
import SwiftData

@Model
final class TrackPoint {
    var lat: Double
    var lon: Double
    var altitude: Double
    var speed: Double
    var timestamp: Date
    var session: Int
    // Added in CSV format 2. nil on points saved before; negative means CoreLocation reported "unknown".
    var rawSpeed: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var speedAccuracy: Double?
    var course: Double?
    var courseAccuracy: Double?
    /// Motion activity when the fix arrived: automotive, walking, cycling, stationary or unknown.
    var activity: String?
    /// CMMotionActivityConfidence raw value: 0 low, 1 medium, 2 high.
    var activityConfidence: Int?

    init(lat: Double, lon: Double, altitude: Double, speed: Double, timestamp: Date, session: Int) {
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
        self.speed = speed
        self.timestamp = timestamp
        self.session = session
    }

    convenience init(location: CLLocation, session: Int, motion: MotionSample? = nil) {
        self.init(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            altitude: location.altitude,
            speed: max(location.speed, 0),
            timestamp: location.timestamp,
            session: session
        )
        // `speed` stays clamped for the analysis code; the raw value keeps -1 distinguishable from 0.
        rawSpeed = location.speed
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        speedAccuracy = location.speedAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        activity = motion?.kind.rawValue
        activityConfidence = motion?.confidence
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
