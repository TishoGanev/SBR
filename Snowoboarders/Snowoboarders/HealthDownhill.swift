//
//  HealthDownhill.swift
//  Snowoboarders
//

import Foundation
import HealthKit
import Combine

/// Reads the downhill distance Apple Health holds for a ride's time window. The watch app records a
/// snowboarding workout while the phone tracks, and watchOS fills in this quantity itself.
@MainActor
final class HealthDownhill: ObservableObject {
    /// Metres, or nil when Health has nothing for the ride (no watch, no permission, no data).
    @Published private(set) var distanceMeters: Double?

    private let store = HKHealthStore()
    private let type = HKQuantityType(.distanceDownhillSnowSports)

    func load(from start: Date, to end: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
        } catch {
            return
        }
        // The workout starts and ends a little either side of the phone's first and last GPS point.
        let predicate = HKQuery.predicateForSamples(
            withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(60)
        )
        let meters: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .meter()))
            }
            store.execute(query)
        }
        distanceMeters = (meters ?? 0) > 0 ? meters : nil
    }
}
