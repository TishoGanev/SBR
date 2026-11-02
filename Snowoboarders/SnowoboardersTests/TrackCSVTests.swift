import XCTest
import CoreLocation
@testable import Snowoboarders

final class TrackCSVTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_792_000_000)

    private func location(at offset: TimeInterval, accuracy: Double = 5, speed: Double = 3, course: Double = 90) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42, longitude: 23),
            altitude: 2000, horizontalAccuracy: accuracy, verticalAccuracy: 8,
            course: course, courseAccuracy: 10, speed: speed, speedAccuracy: 1,
            timestamp: base.addingTimeInterval(offset)
        )
    }

    // MARK: Timestamps

    func testFormatKeepsMilliseconds() {
        XCTAssertEqual(TrackCSV.format(Date(timeIntervalSince1970: 1_792_000_000.95)), "1792000000.950")
    }

    func testParseReadsBothFormats() {
        XCTAssertEqual(TrackCSV.parse("2026-10-14T17:46:40.950Z")?.timeIntervalSince1970 ?? 0, 1_792_000_000.95, accuracy: 0.001)
        XCTAssertEqual(TrackCSV.parse("2026-10-14T17:46:40Z")?.timeIntervalSince1970 ?? 0, 1_792_000_000, accuracy: 0.001)
        XCTAssertEqual(TrackCSV.parse("1792000000.950")?.timeIntervalSince1970 ?? 0, 1_792_000_000.95, accuracy: 0.001)
        XCTAssertNil(TrackCSV.parse("not a date"))
    }

    func testFractionalRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_792_000_000.25)
        XCTAssertEqual(TrackCSV.parse(TrackCSV.format(date))?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: Invalid values

    func testInvalidValuesAreEmptyNotZero() {
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42, longitude: 23),
            altitude: 2000, horizontalAccuracy: 5, verticalAccuracy: -1,
            course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1, timestamp: base
        )
        let fields = TrackCSV.row(TrackPoint(location: invalid, session: 1)).components(separatedBy: ",")
        XCTAssertEqual(fields.count, TrackCSV.columns.count)
        XCTAssertEqual(fields[4], "", "speed -1 must not become 0")
        XCTAssertEqual(fields[5], "5.0")
        XCTAssertEqual(fields[6...9], ["", "", "", ""])
    }

    func testZeroIsKeptWhenValid() {
        let fields = TrackCSV.row(TrackPoint(location: location(at: 0, speed: 0, course: 0), session: 1)).components(separatedBy: ",")
        XCTAssertEqual(fields[4], "0.0")
        XCTAssertEqual(fields[8], "0.0")
    }

    func testVersionOnePointFallsBackToStoredSpeed() {
        let old = TrackPoint(lat: 42, lon: 23, altitude: 2000, speed: 4, timestamp: base, session: 1)
        let fields = TrackCSV.row(old).components(separatedBy: ",")
        XCTAssertEqual(fields[4], "4.0")
        XCTAssertEqual(fields[5...9], ["", "", "", "", ""])
    }

    func testCSVHasVersionLineMetadataAndHeader() {
        let meta = SessionMetadata(rejectedLowAccuracy: 3, rejectedStale: 1)
        let lines = TrackCSV.csv(points: [], metadata: meta).components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "# ridelirium-csv-version: 3")
        XCTAssertTrue(lines.contains("# rejected_low_accuracy: 3"))
        XCTAssertTrue(lines.contains("# rejected_stale: 1"))
        XCTAssertEqual(lines[3], TrackCSV.columns.joined(separator: ","))
    }

    // MARK: Two fixes in neighbouring seconds

    func testFixesAtPoint95AndPoint05GetDifferentTimestamps() {
        // Whole-second output would write both as ...:00 and ...:02, or x.05 and x.95 as the same second.
        let points = [location(at: 0.95), location(at: 2.05), location(at: 3.05), location(at: 3.95)]
            .map { TrackPoint(location: $0, session: 1) }
        let stamps = points.map { TrackCSV.row($0).components(separatedBy: ",")[0] }
        XCTAssertEqual(Set(stamps).count, stamps.count, "\(stamps)")
        XCTAssertEqual(stamps[0], TrackCSV.format(base.addingTimeInterval(0.95)))
        XCTAssertEqual(TrackCSV.parse(stamps[1])!.timeIntervalSince(TrackCSV.parse(stamps[0])!), 1.10, accuracy: 0.002)
    }

    // MARK: Fix filter (bug 5)

    func testFilterRejectsPoorAccuracy() {
        var filter = FixFilter()
        XCTAssertEqual(filter.check(location(at: 0, accuracy: 50)), .accept)
        XCTAssertEqual(filter.check(location(at: 1, accuracy: 50.1)), .lowAccuracy)
        XCTAssertEqual(filter.check(location(at: 2, accuracy: -1)), .lowAccuracy)
        XCTAssertEqual(filter.metadata.rejectedLowAccuracy, 2)
        XCTAssertEqual(filter.metadata.rejectedStale, 0)
    }

    func testFilterRejectsOlderAndRepeatedTimestamps() {
        var filter = FixFilter()
        XCTAssertEqual(filter.check(location(at: 10)), .accept)
        XCTAssertEqual(filter.check(location(at: 9)), .stale)
        XCTAssertEqual(filter.check(location(at: 10)), .stale)
        XCTAssertEqual(filter.check(location(at: 11)), .accept)
        XCTAssertEqual(filter.metadata.rejectedStale, 2)
    }

    func testRejectedFixDoesNotMoveTheLastTimestamp() {
        var filter = FixFilter()
        _ = filter.check(location(at: 10))
        _ = filter.check(location(at: 20, accuracy: 200))
        XCTAssertEqual(filter.check(location(at: 11)), .accept)
    }

    func testFilterRejectsFixCachedFromBeforeRecordingStarted() {
        var filter = FixFilter(notBefore: base)
        XCTAssertEqual(filter.check(location(at: -30)), .stale)
        XCTAssertEqual(filter.check(location(at: 1)), .accept)
    }

    // MARK: Distance rule (bug 6)

    func testSlowStepInsideAccuracyIsNotCounted() {
        XCTAssertFalse(DistanceRule.counts(displacement: 3, speed: 0.2, accuracy: 5))
    }

    func testSlowStepBeyondAccuracyIsCounted() {
        XCTAssertTrue(DistanceRule.counts(displacement: 8, speed: 0.2, accuracy: 5))
    }

    func testFastStepIsAlwaysCounted() {
        XCTAssertTrue(DistanceRule.counts(displacement: 3, speed: 0.5, accuracy: 5))
    }

    func testUnknownSpeedOrAccuracyKeepsTheStep() {
        XCTAssertTrue(DistanceRule.counts(displacement: 3, speed: -1, accuracy: 5))
        XCTAssertTrue(DistanceRule.counts(displacement: 3, speed: nil, accuracy: 5))
        XCTAssertTrue(DistanceRule.counts(displacement: 3, speed: 0, accuracy: nil))
    }

    func testStandingStillAddsNoDistance() {
        // 600 fixes jittering a few metres around one spot, speed 0, accuracy 8 m.
        var points: [TrackPoint] = []
        for i in 0..<600 {
            let jitter = Double(i % 4) * 0.00002
            let point = TrackPoint(lat: 42 + jitter, lon: 23, altitude: 2000, speed: 0, timestamp: base.addingTimeInterval(Double(i)), session: 1)
            point.rawSpeed = 0
            point.horizontalAccuracy = 8
            points.append(point)
        }
        XCTAssertEqual(DistanceRule.steps(points).reduce(0, +), 0, accuracy: 0.001)
    }

    func testRealMovementIsStillCounted() {
        var points: [TrackPoint] = []
        for i in 0..<60 {
            let point = TrackPoint(lat: 42 + Double(i) * 0.00005, lon: 23, altitude: 2000, speed: 5.5, timestamp: base.addingTimeInterval(Double(i)), session: 1)
            point.rawSpeed = 5.5
            point.horizontalAccuracy = 8
            points.append(point)
        }
        XCTAssertEqual(DistanceRule.steps(points).reduce(0, +), 59 * 0.00005 * 111_195, accuracy: 20)
    }

    // MARK: Motion auto control

    func testAutoStopAfterIdleMinutes() {
        var control = MotionAutoControl(autoStop: true, stopAfter: 180)
        let still = MotionSample(kind: .stationary, confidence: 2)
        XCTAssertEqual(control.evaluate(still, now: base, isTracking: true), .none)
        XCTAssertEqual(control.evaluate(still, now: base.addingTimeInterval(179), isTracking: true), .none)
        XCTAssertEqual(control.evaluate(still, now: base.addingTimeInterval(180), isTracking: true), .stop)
    }

    func testMovingResetsIdleTimerAndSettingsOffDoNothing() {
        var control = MotionAutoControl(autoStop: true, stopAfter: 180)
        _ = control.evaluate(MotionSample(kind: .walking, confidence: 2), now: base, isTracking: true)
        _ = control.evaluate(MotionSample(kind: .automotive, confidence: 2), now: base.addingTimeInterval(100), isTracking: true)
        XCTAssertEqual(control.evaluate(MotionSample(kind: .walking, confidence: 2), now: base.addingTimeInterval(250), isTracking: true), .none)

        var off = MotionAutoControl()
        XCTAssertEqual(off.evaluate(MotionSample(kind: .stationary, confidence: 2), now: base.addingTimeInterval(9999), isTracking: true), .none)
        XCTAssertEqual(off.evaluate(MotionSample(kind: .automotive, confidence: 2), now: base, isTracking: false), .none)
    }

    func testAutoStartNeedsDrivingWithConfidence() {
        var control = MotionAutoControl(autoStart: true)
        XCTAssertEqual(control.evaluate(MotionSample(kind: .automotive, confidence: 0), now: base, isTracking: false), .none)
        XCTAssertEqual(control.evaluate(MotionSample(kind: .walking, confidence: 2), now: base, isTracking: false), .none)
        XCTAssertEqual(control.evaluate(MotionSample(kind: .automotive, confidence: 1), now: base, isTracking: false), .start)
    }
}
