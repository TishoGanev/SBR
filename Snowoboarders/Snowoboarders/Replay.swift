//
//  Replay.swift
//  Snowoboarders
//

import SwiftUI
import CoreLocation
import Combine

/// Plays a recorded ride back along its route at 1×–16× speed.
///
/// Time is measured along the recorded timestamps, but any gap longer than `maxGap` (a pause, or GPS
/// dropping out) is squeezed to `maxGap` so the playback doesn't sit still.
@MainActor
final class RideReplay: ObservableObject {
    static let speeds = [1, 2, 4, 8, 16]

    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false
    @Published var speed = 1

    let duration: Double
    private let points: [TrackPoint]
    private let coordinates: [CLLocationCoordinate2D]
    private let offsets: [Double]
    private var timer: Timer?
    private var lastTick = Date()

    private static let maxGap: Double = 5
    private static let chunk = 50
    private static let tickInterval: TimeInterval = 1.0 / 20

    init(points: [TrackPoint]) {
        self.points = points
        coordinates = points.map(\.coordinate)
        var offsets: [Double] = []
        var elapsed = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 {
                elapsed += min(max(point.timestamp.timeIntervalSince(points[index - 1].timestamp), 0), Self.maxGap)
            }
            offsets.append(elapsed)
        }
        self.offsets = offsets
        duration = elapsed
    }

    deinit { timer?.invalidate() }

    var isFinished: Bool { time >= duration }

    // MARK: - Current frame

    /// Index of the last point at or before `time`.
    private var index: Int {
        var low = 0, high = offsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if offsets[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Position between the two surrounding points; nil for a ride with no points.
    var position: CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        let i = index
        guard i + 1 < points.count else { return coordinates[i] }
        let span = offsets[i + 1] - offsets[i]
        let f = span > 0 ? (time - offsets[i]) / span : 0
        return CLLocationCoordinate2D(
            latitude: coordinates[i].latitude + (coordinates[i + 1].latitude - coordinates[i].latitude) * f,
            longitude: coordinates[i].longitude + (coordinates[i + 1].longitude - coordinates[i].longitude) * f
        )
    }

    /// Points in the settled part of the trail. It only grows every `chunk` points, so the long
    /// polyline isn't rebuilt on every frame.
    var committedCount: Int { index / Self.chunk * Self.chunk + 1 }

    var committedTrail: [CLLocationCoordinate2D] { Array(coordinates[0..<min(committedCount, coordinates.count)]) }

    /// The short, changing end of the trail: from the last settled point to the rider.
    var headTrail: [CLLocationCoordinate2D] {
        guard let position else { return [] }
        return Array(coordinates[(committedCount - 1)...index]) + [position]
    }

    var currentSpeed: Double { points.isEmpty ? 0 : points[index].speed }
    var currentAltitude: Double { points.isEmpty ? 0 : points[index].altitude }

    // MARK: - Controls

    func play() {
        guard !points.isEmpty else { return }
        if isFinished { time = 0 }
        isPlaying = true
        lastTick = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func restart() {
        time = 0
        play()
    }

    func seek(to newTime: Double) {
        time = min(max(newTime, 0), duration)
        lastTick = Date()
    }

    private func tick() {
        let now = Date()
        time = min(time + now.timeIntervalSince(lastTick) * Double(speed), duration)
        lastTick = now
        if isFinished { pause() }
    }
}

/// Playback panel shown in place of Share / Export while a ride is being replayed.
struct ReplayControls: View {
    @ObservedObject var replay: RideReplay
    let units: Units
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(units.duration(replay.time)) / \(units.duration(replay.duration))")
                    .font(.sb(16))
                    .monospacedDigit()
                    .foregroundStyle(.sbCharcoal)
                Spacer()
                Button("CLOSE", action: onClose)
                    .font(.sb(16))
                    .foregroundStyle(.sbRed)
            }

            Text("\(units.speed(metersPerSecond: replay.currentSpeed)) · \(units.altitude(meters: replay.currentAltitude))")
                .font(.sb(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(.sbSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Slider(
                value: Binding(get: { replay.time }, set: { replay.seek(to: $0) }),
                in: 0...max(replay.duration, 1)
            ) { editing in
                if editing { replay.pause() }
            }
            .tint(.sbRed)

            HStack(spacing: 6) {
                Button(action: replay.toggle) {
                    Image(systemName: replay.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 52)
                        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(replay.isPlaying ? "Pause" : "Play")

                Button(action: replay.restart) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.sbGreyButtonText)
                        .frame(width: 48, height: 52)
                        .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedBrightness: -0.05))
                .accessibilityLabel("Restart")

                ForEach(RideReplay.speeds, id: \.self) { value in
                    let selected = replay.speed == value
                    Button { replay.speed = value } label: {
                        Text("\(value)×")
                            .font(.sb(18))
                            .foregroundStyle(selected ? Color.white : .sbGreyButtonText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                selected ? Color.sbCharcoal : Color.sbLightGrey,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(PressableStyle(pressedBrightness: -0.05))
                    .accessibilityLabel("\(value) times speed")
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 106)
    }
}
