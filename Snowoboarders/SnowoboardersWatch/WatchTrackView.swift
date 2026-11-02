//
//  WatchTrackView.swift
//  SnowoboardersWatch
//

import SwiftUI

private extension Color {
    static let sbRed = Color(red: 0xED / 255, green: 0x21 / 255, blue: 0x3D / 255)
}

struct WatchTrackView: View {
    @EnvironmentObject private var link: WatchLink
    @EnvironmentObject private var workout: WorkoutManager

    private var state: WatchState { link.state }

    var body: some View {
        VStack(spacing: 6) {
            if state.isTracking {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(format(duration: link.elapsed(at: context.date)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.sbRed)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", speedValue(state.speed)))
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text(state.metric ? "KM/H" : "MPH")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                heartRateLabel
                HStack {
                    stat("DIST", distanceText)
                    Spacer(minLength: 4)
                    stat("MAX", String(format: "%.0f", speedValue(state.maxSpeed)))
                    Spacer(minLength: 4)
                    stat("ALT", altitudeText)
                }
                controls
            } else {
                Spacer(minLength: 0)
                Button { link.send(.start) } label: {
                    Label("START", systemImage: "record.circle")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.sbRed)
                .buttonStyle(.borderedProminent)
                .disabled(!link.isReachable)
                if !link.isReachable {
                    Text("Open the app on your iPhone")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                heartRateLabel
                stat("ALT", altitudeText)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .onAppear { workout.startMonitoring(); workout.sync(tracking: state.isTracking, paused: state.isPaused) }
        .onChange(of: state.isTracking) { workout.sync(tracking: state.isTracking, paused: state.isPaused) }
        .onChange(of: state.isPaused) { workout.sync(tracking: state.isTracking, paused: state.isPaused) }
    }

    private var heartRateLabel: some View {
        Label(workout.heartRate.map { String(Int($0.rounded())) } ?? "--", systemImage: "heart.fill")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.sbRed)
            .accessibilityLabel("Heart rate")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { link.send(state.isPaused ? .resume : .pause) } label: {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityLabel(state.isPaused ? "Resume" : "Pause")
            Button { link.send(.stop) } label: {
                Image(systemName: "stop.fill")
            }
            .tint(Color.sbRed)
            .accessibilityLabel("Stop")
        }
        .disabled(!link.isReachable)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }

    private func speedValue(_ metersPerSecond: Double) -> Double {
        let kmh = max(metersPerSecond, 0) * 3.6
        return state.metric ? kmh : kmh * 0.621
    }

    private var distanceText: String {
        let km = state.distance / 1000
        return String(format: "%.1f", state.metric ? km : km * 0.621)
    }

    private var altitudeText: String {
        guard let altitude = state.altitude else { return "--" }
        return String(Int((state.metric ? altitude : altitude * 3.281).rounded()))
    }

    private func format(duration: TimeInterval) -> String {
        let total = max(Int(duration), 0)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
