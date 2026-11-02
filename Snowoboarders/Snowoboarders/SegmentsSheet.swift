//
//  SegmentsSheet.swift
//  Snowoboarders
//

import SwiftUI

/// Every run, lift and stop of one ride, with a time breakdown on top.
struct SegmentsSheet: View {
    let session: SessionSummary
    let analysis: RideAnalysis
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SEGMENTS")
                .font(.sb(24, .extraBold))
                .foregroundStyle(.sbCharcoal)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)

            HStack(spacing: 10) {
                tile("RIDING", analysis.duration(of: .run), .sbRed)
                tile("ON LIFT", analysis.duration(of: .lift), .sbLift)
                tile("STOPPED", analysis.duration(of: .still), .sbStill)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
        }
        .background(Color.white)
    }

    private struct Row: Identifiable {
        let segment: Segment
        let title: String
        var id: Int { segment.id }
    }

    /// Numbers runs and lifts separately: RUN 1, LIFT 1, RUN 2…
    private var rows: [Row] {
        var runs = 0, lifts = 0
        return analysis.segments.map { segment in
            switch segment.activity {
            case .run: runs += 1; return Row(segment: segment, title: "RUN \(runs)")
            case .lift: lifts += 1; return Row(segment: segment, title: "LIFT \(lifts)")
            case .still: return Row(segment: segment, title: "STOPPED")
            }
        }
    }

    private func tile(_ title: String, _ seconds: TimeInterval, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.sb(13)).tracking(13 * 0.04).foregroundStyle(.sbSecondary)
            }
            Text(units.compactDuration(seconds))
                .font(.sbFixed(24))
                .monospacedDigit()
                .foregroundStyle(.sbCharcoal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rowView(_ row: Row) -> some View {
        let segment = row.segment
        let start = session.points[segment.startIndex].timestamp
        return HStack(spacing: 12) {
            Circle().fill(color(for: segment.activity)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.sb(18)).foregroundStyle(.sbCharcoal)
                Text("\(start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))) · \(units.duration(segment.duration))")
                    .font(.sb(14, .semibold)).monospacedDigit().foregroundStyle(.sbSecondary)
            }
            Spacer()
            if segment.activity != .still {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(units.distance(meters: segment.distance))
                        .font(.sb(16)).monospacedDigit().foregroundStyle(.sbCharcoal)
                    Text(detail(segment))
                        .font(.sb(14, .semibold)).monospacedDigit().foregroundStyle(.sbSecondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.sbDivider).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ segment: Segment) -> String {
        switch segment.activity {
        case .run: "↓ \(units.altitude(meters: segment.vertical)) · \(units.speed(metersPerSecond: segment.maxSpeed))"
        case .lift: "↑ \(units.altitude(meters: segment.vertical))"
        case .still: ""
        }
    }

    private func color(for activity: Activity) -> Color {
        switch activity {
        case .run: .sbRed
        case .lift: .sbLift
        case .still: .sbStill
        }
    }
}
