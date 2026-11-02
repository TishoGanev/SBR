import XCTest
import CoreLocation
@testable import Snowoboarders

final class ActivityDetectorTests: XCTestCase {
    /// One point per second; `dAlt` metres of altitude and `dLat` degrees of latitude per step.
    private func leg(from last: TrackPoint?, steps: Int, dAlt: Double, dLat: Double, speed: Double) -> [TrackPoint] {
        var current = last ?? TrackPoint(lat: 42, lon: 23, altitude: 2000, speed: speed, timestamp: Date(timeIntervalSinceReferenceDate: 0), session: 1)
        var out: [TrackPoint] = []
        for _ in 0..<steps {
            current = TrackPoint(
                lat: current.lat + dLat, lon: current.lon, altitude: current.altitude + dAlt,
                speed: speed, timestamp: current.timestamp.addingTimeInterval(1), session: 1
            )
            out.append(current)
        }
        return out
    }

    func testRunStillLift() {
        let run = leg(from: nil, steps: 120, dAlt: -1.5, dLat: 0.00006, speed: 7)
        let still = leg(from: run.last, steps: 120, dAlt: 0, dLat: 0, speed: 0.1)
        let lift = leg(from: still.last, steps: 200, dAlt: 0.9, dLat: -0.00002, speed: 2.5)
        let analysis = ActivityDetector.analyze(run + still + lift)

        XCTAssertEqual(analysis.segments.map(\.activity), [.run, .still, .lift])
        XCTAssertEqual(analysis.runs.count, 1)
        XCTAssertEqual(analysis.lifts.count, 1)
        XCTAssertEqual(analysis.totalVertical, 180, accuracy: 25)
        XCTAssertEqual(analysis.liftVertical, 180, accuracy: 25)
    }

    func testStandingStillIsNotARun() {
        let analysis = ActivityDetector.analyze(leg(from: nil, steps: 200, dAlt: 0, dLat: 0, speed: 0))
        XCTAssertTrue(analysis.runs.isEmpty)
        XCTAssertEqual(analysis.movingDistance, 0, accuracy: 0.01)
    }

    func testShortFlatTraverseDoesNotSplitARun() {
        let a = leg(from: nil, steps: 60, dAlt: -1.5, dLat: 0.00006, speed: 7)
        let flat = leg(from: a.last, steps: 10, dAlt: 0, dLat: 0.00004, speed: 4)
        let b = leg(from: flat.last, steps: 60, dAlt: -1.5, dLat: 0.00006, speed: 7)
        XCTAssertEqual(ActivityDetector.analyze(a + flat + b).runs.count, 1)
    }

    func testInsightFacts() {
        let run1 = leg(from: nil, steps: 120, dAlt: -1.5, dLat: 0.00006, speed: 7)
        let lift = leg(from: run1.last, steps: 200, dAlt: 0.9, dLat: -0.00002, speed: 2.5)
        let run2 = leg(from: lift.last, steps: 100, dAlt: -1.5, dLat: 0.00006, speed: 9)
        let points = run1 + lift + run2
        let facts = RideInsightFacts(analysis: ActivityDetector.analyze(points), points: points, placeName: "Test", units: Units(metric: true))

        XCTAssertTrue(facts.bullets.contains { $0.contains("Run 2 was your fastest") }, "\(facts.bullets)")
        XCTAssertTrue(facts.bullets.contains { $0.contains("1 lift") }, "\(facts.bullets)")
        XCTAssertTrue(facts.prompt.contains("Runs: 2"))
    }

    func testFlatRideStillCountsDistance() {
        let analysis = ActivityDetector.analyze(leg(from: nil, steps: 200, dAlt: 0, dLat: 0.00002, speed: 1.5))
        XCTAssertGreaterThan(analysis.movingDistance, 300)
    }

    func testRideWithNoSpeedDataStillCountsDistance() {
        let analysis = ActivityDetector.analyze(leg(from: nil, steps: 200, dAlt: 0, dLat: 0.00004, speed: 0))
        XCTAssertGreaterThan(analysis.movingDistance, 600)
    }

    func testLiveClassifierStartsOnTheFlat() {
        var live = LiveActivityClassifier()
        for point in leg(from: nil, steps: 12, dAlt: 0, dLat: 0.00002, speed: 1.5) {
            live.add(CLLocation(
                coordinate: point.coordinate, altitude: point.altitude, horizontalAccuracy: 5, verticalAccuracy: 5,
                course: 0, speed: point.speed, timestamp: point.timestamp
            ))
        }
        XCTAssertEqual(live.activity, .run)
    }

    func testWalkBetweenTwoStopsKeepsItsDistance() {
        let start = leg(from: nil, steps: 60, dAlt: 0, dLat: 0, speed: 0)
        let walk = leg(from: start.last, steps: 120, dAlt: 0, dLat: 0.00002, speed: 1.4)
        let end = leg(from: walk.last, steps: 60, dAlt: 0, dLat: 0, speed: 0)
        XCTAssertGreaterThan(ActivityDetector.analyze(start + walk + end).movingDistance, 200)
    }
}
