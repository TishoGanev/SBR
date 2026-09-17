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

    init(lat: Double, lon: Double, altitude: Double, speed: Double, timestamp: Date, session: Int) {
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
        self.speed = speed
        self.timestamp = timestamp
        self.session = session
    }

    convenience init(location: CLLocation, session: Int) {
        self.init(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            altitude: location.altitude,
            speed: max(location.speed, 0),
            timestamp: location.timestamp,
            session: session
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
