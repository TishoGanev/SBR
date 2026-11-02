//
//  ActivityDetector.swift
//  Snowoboarders
//

import Foundation
import CoreLocation

/// What the rider was doing: descending, riding a lift, or standing still.
enum Activity: Hashable {
    case run, lift, still
}

/// A stretch of a ride with one activity.
struct Segment: Identifiable {
    let activity: Activity
    let startIndex: Int
    let endIndex: Int
    let distance: Double
    /// Metres descended for a run, metres climbed for a lift, 0 when standing.
    let vertical: Double
    let maxSpeed: Double
    let duration: TimeInterval

    var id: Int { startIndex }
    var averageSpeed: Double { duration > 0 ? distance / duration : 0 }
}

struct RideAnalysis {
    let segments: [Segment]

    var runs: [Segment] { segments.filter { $0.activity == .run } }
    var lifts: [Segment] { segments.filter { $0.activity == .lift } }
    var stills: [Segment] { segments.filter { $0.activity == .still } }

    var downhillDistance: Double { runs.reduce(0) { $0 + $1.distance } }
    var totalVertical: Double { runs.reduce(0) { $0 + $1.vertical } }
    var liftVertical: Double { lifts.reduce(0) { $0 + $1.vertical } }

    /// Distance covered while not standing; GPS drift from a stopped rider is left out.
    var movingDistance: Double { segments.filter { $0.activity != .still }.reduce(0) { $0 + $1.distance } }
    var movingMaxSpeed: Double { segments.filter { $0.activity != .still }.map(\.maxSpeed).max() ?? 0 }

    func duration(of activity: Activity) -> TimeInterval {
        segments.filter { $0.activity == activity }.reduce(0) { $0 + $1.duration }
    }

    static let empty = RideAnalysis(segments: [])
}

/// Splits a recorded ride into runs, lifts and stops from altitude and speed.
///
/// Keep in sync with `ActivityDetector.kt` on Android; both use the same thresholds.
enum ActivityDetector {
    enum Raw { case run, lift, still, flat }

    /// Smoothed descent faster than this (m/s) is a run; climb faster than `liftRate` is a lift.
    static let runRate = -0.25
    static let liftRate = 0.2
    /// Standing still: slow by the GPS speed and not covering ground either.
    static let stillSpeed = 0.6
    static let movingDisplacement = 2.0

    private static let minDuration: [Activity: TimeInterval] = [.run: 15, .lift: 30, .still: 20]
    private static let minRunDrop = 15.0, minRunDistance = 75.0
    private static let minLiftClimb = 15.0, minLiftDistance = 100.0

    /// One point's label from a smoothed vertical rate and ground speed. `.flat` means moving without
    /// clearly climbing or descending, so it takes on its neighbours' label.
    static func raw(rate: Double, speed: Double, displacementSpeed: Double) -> Raw {
        if speed < stillSpeed && displacementSpeed < movingDisplacement { return .still }
        if rate < runRate { return .run }
        if rate > liftRate { return .lift }
        return .flat
    }

    static func analyze(_ points: [TrackPoint]) -> RideAnalysis {
        let n = points.count
        guard n >= 3 else { return .empty }

        let times = points.map { $0.timestamp.timeIntervalSinceReferenceDate }
        let altitude = smoothed(points.map(\.altitude), radius: 2)
        let speed = smoothed(points.map(\.speed), radius: 2)
        let locations = points.map { CLLocation(latitude: $0.lat, longitude: $0.lon) }

        // segment[i] is the horizontal distance added by point i.
        // Steps that are only GPS noise (slow, smaller than the fix accuracy) count as 0.
        let segment = DistanceRule.steps(points)

        // Some recordings carry no GPS speed at all (every value 0). Then ground speed has to come
        // from the distance covered, or the whole ride would look like standing still.
        let hasSpeed = points.contains { $0.speed > 0.5 }

        var raws = [Raw](repeating: .flat, count: n)
        for i in 0..<n {
            let lo = max(0, i - 3), hi = min(n - 1, i + 3)
            let dt = times[hi] - times[lo]
            guard dt > 0 else { continue }
            let displacement = locations[hi].distance(from: locations[lo]) / dt
            raws[i] = raw(
                rate: (altitude[hi] - altitude[lo]) / dt,
                speed: hasSpeed ? speed[i] : displacement,
                displacementSpeed: displacement
            )
        }

        var ranges = group(resolve(raws))

        func stats(_ r: (activity: Activity, start: Int, end: Int)) -> (distance: Double, drop: Double, duration: TimeInterval) {
            let distance = r.end > r.start ? segment[(r.start + 1)...r.end].reduce(0, +) : 0
            return (distance, altitude[r.start] - altitude[r.end], times[r.end] - times[r.start])
        }

        func isValid(_ r: (activity: Activity, start: Int, end: Int)) -> Bool {
            let s = stats(r)
            guard s.duration >= minDuration[r.activity] ?? 0 else { return false }
            switch r.activity {
            case .run: return s.drop >= minRunDrop && s.distance >= minRunDistance
            case .lift: return -s.drop >= minLiftClimb && s.distance >= minLiftDistance
            case .still: return true
            }
        }

        // A stretch too short or too small to count takes on a neighbour's activity. Movement that is
        // merely small (a flat walk between two stops) is kept: dropping it would erase real distance.
        var i = 0
        while ranges.count > 1, i < ranges.count {
            let range = ranges[i]
            if isValid(range) { i += 1; continue }
            let tooShort = stats(range).duration < minDuration[range.activity] ?? 0
            let movingNeighbour = [i - 1, i + 1].first { $0 >= 0 && $0 < ranges.count && ranges[$0].activity != .still }
            if range.activity == .still || tooShort {
                ranges[i].activity = i > 0 ? ranges[i - 1].activity : ranges[i + 1].activity
            } else if let neighbour = movingNeighbour {
                ranges[i].activity = ranges[neighbour].activity
            } else {
                i += 1
                continue
            }
            ranges = merge(ranges)
            i = max(0, i - 1)
        }

        let segments = ranges.map { r -> Segment in
            let s = stats(r)
            let vertical: Double
            switch r.activity {
            case .run: vertical = max(s.drop, 0)
            case .lift: vertical = max(-s.drop, 0)
            case .still: vertical = 0
            }
            return Segment(
                activity: r.activity,
                startIndex: r.start,
                endIndex: r.end,
                distance: s.distance,
                vertical: vertical,
                maxSpeed: points[r.start...r.end].map(\.speed).max() ?? 0,
                duration: s.duration
            )
        }
        return RideAnalysis(segments: segments)
    }

    /// Flat points follow what came before; after a stop they follow the next run or lift.
    private static func resolve(_ raws: [Raw]) -> [Activity] {
        var labels = [Activity?](repeating: nil, count: raws.count)
        var current: Activity?
        for (i, raw) in raws.enumerated() {
            switch raw {
            case .run: current = .run; labels[i] = .run
            case .lift: current = .lift; labels[i] = .lift
            case .still: current = .still; labels[i] = .still
            case .flat: labels[i] = current == .still ? nil : current
            }
        }
        // Moving on the flat is never standing: it follows the next run or lift, else it is riding.
        var next: Activity = .run
        for i in labels.indices.reversed() {
            if let label = labels[i] { next = label == .still ? .run : label } else { labels[i] = next }
        }
        return labels.map { $0 ?? .run }
    }

    private static func group(_ labels: [Activity]) -> [(activity: Activity, start: Int, end: Int)] {
        var ranges: [(activity: Activity, start: Int, end: Int)] = []
        for (i, label) in labels.enumerated() {
            if let last = ranges.last, last.activity == label {
                ranges[ranges.count - 1].end = i
            } else {
                ranges.append((label, i, i))
            }
        }
        return ranges
    }

    private static func merge(_ ranges: [(activity: Activity, start: Int, end: Int)]) -> [(activity: Activity, start: Int, end: Int)] {
        var merged: [(activity: Activity, start: Int, end: Int)] = []
        for range in ranges {
            if let last = merged.last, last.activity == range.activity {
                merged[merged.count - 1].end = range.end
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Moving average; GPS altitude and speed are too noisy to use raw.
    private static func smoothed(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in
            let window = values[max(0, i - radius)...min(values.count - 1, i + radius)]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}

/// Labels the rider live from the last few GPS fixes. A label only changes after three agreeing fixes,
/// so one noisy fix doesn't flip it.
struct LiveActivityClassifier {
    private struct Sample {
        let time: Double
        let altitude: Double
        let speed: Double
        let location: CLLocation
    }

    private var samples: [Sample] = []
    private var candidate: Activity?
    private var candidateCount = 0
    private(set) var activity: Activity = .still

    mutating func reset() {
        samples = []
        candidate = nil
        candidateCount = 0
        activity = .still
    }

    mutating func add(_ location: CLLocation) {
        samples.append(Sample(
            time: location.timestamp.timeIntervalSinceReferenceDate,
            altitude: location.altitude,
            speed: max(location.speed, 0),
            location: location
        ))
        if samples.count > 8 { samples.removeFirst() }
        guard samples.count >= 4, let first = samples.first, let last = samples.last else { return }

        let speed = mean(samples.suffix(5).map(\.speed))
        let head = Array(samples.prefix(3)), tail = Array(samples.suffix(3))
        let dt = mean(tail.map(\.time)) - mean(head.map(\.time))
        let rate = dt > 0 ? (mean(tail.map(\.altitude)) - mean(head.map(\.altitude))) / dt : 0
        let span = last.time - first.time
        let displacement = span > 0 ? last.location.distance(from: first.location) / span : 0

        let target: Activity?
        switch ActivityDetector.raw(rate: rate, speed: speed, displacementSpeed: displacement) {
        case .run: target = .run
        case .lift: target = .lift
        case .still: target = .still
        // Flat but moving: keep a lift or run going, but moving off from a stop means riding.
        case .flat: target = activity == .still ? .run : nil
        }
        guard let target, target != activity else {
            candidate = nil
            candidateCount = 0
            return
        }
        candidateCount = candidate == target ? candidateCount + 1 : 1
        candidate = target
        if candidateCount >= 3 {
            activity = target
            candidate = nil
            candidateCount = 0
        }
    }
}

private func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}
