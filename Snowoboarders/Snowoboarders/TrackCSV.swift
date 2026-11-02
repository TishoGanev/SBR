//
//  TrackCSV.swift
//  Snowoboarders
//

import Foundation
import CoreLocation

/// Session CSV export, plus the rules that decide which GPS fixes are recorded and counted.
///
/// Format versions (first line of the file tells which one; no such line means version 1):
/// - 1: `timestamp,latitude,longitude,altitude_m,speed_mps`; whole-second timestamps, invalid speed written as 0.
/// - 2: `# ridelirium-csv-version: 2` and `# key: value` comment lines, ISO 8601 timestamps with milliseconds,
///   accuracy, course and activity columns; invalid values are empty fields. Read with `comment='#'` in pandas.
/// - 3: as 2, but `timestamp` is unix time in seconds with milliseconds (`1792000000.950`).
enum TrackCSV {
    static let formatVersion = 3

    static let columns = [
        "timestamp", "latitude", "longitude", "altitude_m", "speed_mps",
        "horizontal_accuracy_m", "vertical_accuracy_m", "speed_accuracy_mps",
        "course_deg", "course_accuracy_deg", "activity", "activity_confidence",
    ]

    // MARK: Timestamps

    /// Unix time in seconds with milliseconds, e.g. `1792000000.950`. Timezone-free, and the fraction
    /// keeps two fixes of one second apart (whole seconds made them share a timestamp).
    static func format(_ date: Date) -> String {
        String(format: "%.3f", (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// Reads unix time, and also the ISO 8601 text of versions 1 and 2 (with or without fractions).
    static func parse(_ text: String) -> Date? {
        if let seconds = Double(text), seconds.isFinite { return Date(timeIntervalSince1970: seconds) }
        return fractionalFormatter().date(from: text) ?? wholeSecondFormatter().date(from: text)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func wholeSecondFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    // MARK: Rows

    /// CoreLocation reports "unknown" as a negative number. That is not 0, so it becomes an empty field.
    static func field(_ value: Double?) -> String {
        guard let value, value >= 0 else { return "" }
        return String(value)
    }

    /// Altitude and coordinates are signed, so only a missing value is empty.
    private static func signed(_ value: Double) -> String { String(value) }

    static func row(_ point: TrackPoint) -> String {
        // Points saved before version 2 only have the clamped `speed`; newer ones keep CoreLocation's raw value.
        let speed = point.rawSpeed ?? point.speed
        let activity = point.activity ?? ""
        let confidence = point.activityConfidence.map(String.init) ?? ""
        return [
            format(point.timestamp), signed(point.lat), signed(point.lon), signed(point.altitude), field(speed),
            field(point.horizontalAccuracy), field(point.verticalAccuracy), field(point.speedAccuracy),
            field(point.course), field(point.courseAccuracy), activity, confidence,
        ].joined(separator: ",")
    }

    static func csv(points: [TrackPoint], metadata: SessionMetadata = SessionMetadata()) -> String {
        var lines = ["# ridelirium-csv-version: \(formatVersion)"]
        lines += metadata.commentLines
        lines.append(columns.joined(separator: ","))
        lines += points.map(row)
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Facts about one recording that the points themselves don't carry.
struct SessionMetadata: Codable, Equatable {
    var rejectedLowAccuracy = 0
    var rejectedStale = 0

    var commentLines: [String] {
        ["# rejected_low_accuracy: \(rejectedLowAccuracy)", "# rejected_stale: \(rejectedStale)"]
    }

    private static func key(_ session: Int) -> String { "sessionMetadata.\(session)" }

    static func load(session: Int, defaults: UserDefaults = .standard) -> SessionMetadata {
        defaults.data(forKey: key(session)).flatMap { try? JSONDecoder().decode(SessionMetadata.self, from: $0) }
            ?? SessionMetadata()
    }

    func save(session: Int, defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key(session))
    }
}

/// Decides whether a GPS fix is recorded. A fix with poor accuracy (indoors) or an older timestamp than
/// the last recorded one (a cached position replayed by the system) is dropped and counted.
struct FixFilter {
    var maxHorizontalAccuracy: CLLocationDistance = 50
    /// Fixes stamped before this are cached from before recording began.
    var notBefore: Date?
    private(set) var lastTimestamp: Date?
    private(set) var metadata = SessionMetadata()

    enum Verdict: Equatable { case accept, lowAccuracy, stale }

    init(maxHorizontalAccuracy: CLLocationDistance = 50, notBefore: Date? = nil) {
        self.maxHorizontalAccuracy = maxHorizontalAccuracy
        self.notBefore = notBefore
    }

    /// Equal timestamps count as stale: two points in one instant are what broke the speed calculation.
    mutating func check(_ location: CLLocation) -> Verdict {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > maxHorizontalAccuracy {
            metadata.rejectedLowAccuracy += 1
            return .lowAccuracy
        }
        if let lastTimestamp, location.timestamp <= lastTimestamp {
            metadata.rejectedStale += 1
            return .stale
        }
        if let notBefore, location.timestamp < notBefore {
            metadata.rejectedStale += 1
            return .stale
        }
        lastTimestamp = location.timestamp
        return .accept
    }
}

/// GPS noise while standing adds distance from nothing. A step that is slow and smaller than the
/// fix's own uncertainty is noise.
enum DistanceRule {
    static let slowSpeed = 0.5

    /// - Parameters:
    ///   - speed: CoreLocation speed; negative or nil means unknown, and then the step is kept.
    ///   - accuracy: horizontal accuracy; nil or negative (older points) means the step is kept.
    static func counts(displacement: CLLocationDistance, speed: Double?, accuracy: CLLocationDistance?) -> Bool {
        guard let speed, speed >= 0, let accuracy, accuracy >= 0 else { return true }
        return !(speed < slowSpeed && displacement < accuracy)
    }

    /// Distance added at each point, 0 for the first. A dropped step keeps the old anchor, so a slow
    /// but real drift still counts once it is larger than the accuracy.
    static func steps(_ points: [TrackPoint]) -> [Double] {
        var steps = [Double](repeating: 0, count: points.count)
        guard var anchor = points.first.map({ CLLocation(latitude: $0.lat, longitude: $0.lon) }) else { return steps }
        for i in 1..<max(points.count, 1) {
            let point = points[i]
            let location = CLLocation(latitude: point.lat, longitude: point.lon)
            let distance = location.distance(from: anchor)
            if counts(displacement: distance, speed: point.rawSpeed, accuracy: point.horizontalAccuracy) {
                steps[i] = distance
                anchor = location
            }
        }
        return steps
    }
}
