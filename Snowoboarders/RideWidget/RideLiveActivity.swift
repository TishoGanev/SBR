//
//  RideLiveActivity.swift
//  RideWidget
//
//  Lock Screen banner and Dynamic Island for a ride in progress.
//

import ActivityKit
import SwiftUI
import WidgetKit

private extension Color {
    static let sbRed = Color(red: 0xED / 255, green: 0x21 / 255, blue: 0x3D / 255)
    static let sbCharcoal = Color(red: 0x35 / 255, green: 0x35 / 255, blue: 0x35 / 255)
    static let sbSecondary = Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8A / 255)
}

private extension Font {
    /// The app's Open Sans Condensed isn't bundled with the extension; condensed heavy system type is close.
    static func ride(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

private struct RideFormat {
    let metric: Bool

    func speed(_ metersPerSecond: Double) -> String {
        let kmh = max(metersPerSecond, 0) * 3.6
        return String(format: "%.0f", metric ? kmh : kmh * 0.621)
    }

    func distance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.2f", metric ? km : km * 0.621)
    }

    var speedUnit: String { metric ? "KM/H" : "MPH" }
    var distanceUnit: String { metric ? "KM" : "MI" }
}

private extension RideActivityAttributes.ContentState {
    var isPaused: Bool { pausedElapsed != nil }

    var label: String {
        if isPaused { return "PAUSED" }
        switch motion {
        case .run: return "RIDING"
        case .lift: return "ON THE LIFT"
        case .still: return "STOPPED"
        }
    }

    var symbol: String {
        if isPaused { return "pause.fill" }
        switch motion {
        case .run: return "figure.snowboarding"
        case .lift: return "cablecar.fill"
        case .still: return "figure.stand"
        }
    }
}

/// Counts up on its own while riding; shows the frozen time while paused.
private struct RideTimer: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(Duration.seconds(paused).formatted(.time(pattern: paused >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

struct RideLiveActivity: Widget {
    /// Tapping the banner or the island opens the app on the ride, not wherever it was last left.
    private static let rideURL = URL(string: "snowboarder://ride")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state, format: RideFormat(metric: context.attributes.metric))
                .activityBackgroundTint(.sbCharcoal)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.rideURL)
        } dynamicIsland: { context in
            let state = context.state
            let format = RideFormat(metric: context.attributes.metric)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Stat(value: format.speed(state.speed), unit: format.speedUnit)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Stat(value: format.distance(state.distance), unit: format.distanceUnit, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(state.label, systemImage: state.symbol)
                            .font(.ride(14, .bold))
                            .foregroundStyle(Color.sbRed)
                        Spacer()
                        RideTimer(state: state)
                            .font(.ride(18))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(Color.sbRed)
            } compactTrailing: {
                Text(format.speed(state.speed))
                    .font(.ride(15))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(Color.sbRed)
            }
            .keylineTint(.sbRed)
            .widgetURL(Self.rideURL)
        }
    }
}

private struct LockScreenView: View {
    let state: RideActivityAttributes.ContentState
    let format: RideFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.label, systemImage: state.symbol)
                    .font(.ride(15, .bold))
                    .foregroundStyle(Color.sbRed)
                Spacer()
                RideTimer(state: state)
                    .font(.ride(17))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
            HStack(alignment: .firstTextBaseline) {
                Stat(value: format.speed(state.speed), unit: format.speedUnit, size: 44)
                Spacer()
                Stat(value: format.distance(state.distance), unit: format.distanceUnit, size: 28, alignment: .trailing)
                Stat(value: format.speed(state.maxSpeed), unit: "MAX", size: 28, alignment: .trailing)
                    .padding(.leading, 14)
            }
        }
        .padding(16)
    }
}

private struct Stat: View {
    let value: String
    let unit: String
    var size: CGFloat = 30
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.ride(size))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.ride(11, .bold))
                .foregroundStyle(Color.sbSecondary)
        }
    }
}
