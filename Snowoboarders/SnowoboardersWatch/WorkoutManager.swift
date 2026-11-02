//
//  WorkoutManager.swift
//  SnowoboardersWatch
//

import Foundation
import HealthKit

/// Runs a snowboarding workout on the watch while the phone is tracking, which supplies live heart rate
/// and keeps the app running in the background.
final class WorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published private(set) var heartRate: Double?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var starting = false
    private var monitorQuery: HKAnchoredObjectQuery?

    private let heartRateType = HKQuantityType(.heartRate)

    /// Shows the most recent heart rate while no workout is running.
    func startMonitoring() {
        guard HKHealthStore.isHealthDataAvailable(), monitorQuery == nil else { return }
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartRateType]) { [weak self] ok, _ in
            guard ok, let self else { return }
            DispatchQueue.main.async { self.runMonitorQuery() }
        }
    }

    private func runMonitorQuery() {
        guard monitorQuery == nil else { return }
        let recent = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: nil)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            guard let self, self.session == nil,
                  let sample = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async { self.heartRate = bpm }
        }
        let query = HKAnchoredObjectQuery(type: heartRateType, predicate: recent, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        monitorQuery = query
    }

    /// Follow the phone's tracking state.
    func sync(tracking: Bool, paused: Bool) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if tracking {
            if session == nil {
                start()
            } else if paused, session?.state == .running {
                session?.pause()
            } else if !paused, session?.state == .paused {
                session?.resume()
            }
        } else {
            end()
        }
    }

    private func start() {
        guard !starting else { return }
        starting = true
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType]
        store.requestAuthorization(toShare: share, read: read) { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.starting = false
                if ok { self.begin() }
            }
        }
    }

    private func begin() {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .snowboarding
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    private func end() {
        starting = false
        guard let session, session.state != .ended, session.state != .stopped else { return }
        session.end()
    }

    private func finish(date: Date) {
        let builder = self.builder
        session = nil
        self.builder = nil
        DispatchQueue.main.async { self.heartRate = nil }
        builder?.endCollection(withEnd: date) { _, _ in
            builder?.finishWorkout { _, _ in }
        }
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended { finish(date: date) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        finish(date: Date())
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(heartRateType),
              let quantity = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.heartRate = bpm }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
