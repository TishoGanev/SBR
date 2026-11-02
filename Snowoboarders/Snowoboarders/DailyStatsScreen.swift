//
//  DailyStatsScreen.swift
//  Snowoboarders
//

import SwiftUI
import MapKit
import UIKit

struct DailyStatsScreen: View {
    let session: SessionSummary
    let placeName: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitsMetric") private var unitsMetric = true
    @State private var cameraPosition: MapCameraPosition
    @State private var shareContent: ShareContent?
    @State private var isPreparingShare = false
    @StateObject private var replay: RideReplay
    @State private var isReplaying = false
    @StateObject private var health = HealthDownhill()
    /// Computed once: the replay redraws the map ~20 times a second.
    private let routeCoordinates: [CLLocationCoordinate2D]
    private let analysis: RideAnalysis
    private let routeParts: [RoutePart]
    private let stillSpots: [CLLocationCoordinate2D]
    @State private var showSegments = false
    @State private var showInsights = false
    @StateObject private var insights = RideInsightsModel()
    private let insightFacts: RideInsightFacts
    @State private var committed: [CLLocationCoordinate2D] = []

    private var units: Units { Units(metric: unitsMetric) }

    init(session: SessionSummary, placeName: String) {
        self.session = session
        self.placeName = placeName
        routeCoordinates = session.coordinates
        let analysis = session.analysis
        self.analysis = analysis
        let coordinates = session.coordinates
        routeParts = analysis.segments.filter { $0.activity != .still }.map { segment in
            // Run one point into the next segment so the coloured lines join up.
            let end = min(segment.endIndex + 1, coordinates.count - 1)
            return RoutePart(id: segment.id, activity: segment.activity, coordinates: Array(coordinates[segment.startIndex...end]))
        }
        insightFacts = RideInsightFacts(
            analysis: analysis, points: session.points, placeName: placeName,
            units: Units(metric: UserDefaults.standard.object(forKey: "unitsMetric") as? Bool ?? true)
        )
        stillSpots = analysis.stills.map { coordinates[($0.startIndex + $0.endIndex) / 2] }
        _cameraPosition = State(initialValue: .rect(Self.routeRect(for: session.coordinates)))
        _replay = StateObject(wrappedValue: RideReplay(points: session.points))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            map
            if isReplaying {
                ReplayControls(replay: replay, units: units, onClose: closeReplay)
            } else {
                buttons
            }
        }
        .task { await health.load(from: session.startDate, to: session.endDate) }
        .onDisappear { replay.pause() }
        .onChange(of: replay.committedCount) { _, _ in committed = replay.committedTrail }
        .onChange(of: isReplaying) { _, _ in committed = replay.committedTrail }
        .background(Color.white)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showInsights) {
            InsightsSheet(model: insights, facts: insightFacts)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSegments) {
            SegmentsSheet(session: session, analysis: analysis, units: units)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareContent) { content in
            ActivityView(items: content.items)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackLink(title: "STATS") { dismiss() }

            Text(kicker)
                .font(.sb(18))
                .tracking(18 * 0.04)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .cssLineHeight(1, fontSize: 18)
                .padding(.top, 8)

            HeroNumber(
                value: String(format: "%.1f", units.distanceValue(meters: session.distance)),
                captionLines: [
                    units.distanceUnit.uppercased(),
                    "\(units.speed(metersPerSecond: session.maxSpeed)) MAX",
                ]
            )
            .padding(.top, 6)

            if let healthMeters = health.distanceMeters {
                Text("APPLE HEALTH · \(units.distance(meters: healthMeters)) DOWNHILL")
                    .font(.sb(14))
                    .tracking(14 * 0.04)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.88)
                    .padding(.top, 4)
            }
            if !analysis.segments.isEmpty {
                Button { showSegments = true } label: {
                    HStack(spacing: 6) {
                        Text(breakdown)
                            .font(.sb(14))
                            .tracking(14 * 0.04)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Chevron(color: .white, lineWidth: 2.5, size: 9)
                    }
                    .opacity(0.88)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Show runs and lifts")
            }
            Button { showInsights = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI INSIGHTS")
                            .font(.sb(22))
                            .tracking(22 * 0.04)
                            .cssLineHeight(1, fontSize: 22)
                        Text("A SUMMARY OF THIS RIDE")
                            .font(.sb(13))
                            .tracking(13 * 0.06)
                            .opacity(0.7)
                            .cssLineHeight(1, fontSize: 13)
                    }
                    Spacer(minLength: 0)
                    Chevron(color: .sbRed, lineWidth: 3, size: 12)
                }
                .foregroundStyle(Color.sbRed)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .sbShadow(y: 8, blur: 20, opacity: 0.3)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 16)
            .accessibilityLabel("Ride insights")

            if !analysis.runs.isEmpty {
                Text(runSummary)
                    .font(.sb(14))
                    .tracking(14 * 0.04)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.88)
                    .padding(.top, 10)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 58)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .background(Color.sbRed)
    }

    private var runSummary: String {
        let count = analysis.runs.count
        return "\(count) \(count == 1 ? "RUN" : "RUNS") · \(units.distance(meters: analysis.downhillDistance)) DOWNHILL · "
            + "\(units.altitude(meters: analysis.totalVertical)) DESCENT"
    }

    private var breakdown: String {
        let lifts = analysis.lifts.count
        return "RIDING \(units.compactDuration(analysis.duration(of: .run))) · "
            + "\(lifts) \(lifts == 1 ? "LIFT" : "LIFTS") \(units.compactDuration(analysis.duration(of: .lift))) · "
            + "STOPPED \(units.compactDuration(analysis.duration(of: .still)))"
    }

    private var kicker: String {
        let day = session.startDate.formatted(.dateTime.day(.twoDigits).month(.abbreviated)).uppercased()
        let start = session.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let end = session.endDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(placeName.uppercased()) · \(day) · \(start)–\(end)"
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if isReplaying {
                routeLines(opacity: 0.3)
                MapPolyline(coordinates: committed)
                    .stroke(Color.sbRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: replay.headTrail)
                    .stroke(Color.sbRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let position = replay.position {
                    Annotation("", coordinate: position, anchor: .center) { UserDot() }
                        .annotationTitles(.hidden)
                }
            } else {
                routeLines(opacity: 1)
                ForEach(Array(stillSpots.enumerated()), id: \.offset) { _, spot in
                    Annotation("Stopped", coordinate: spot, anchor: .center) {
                        Circle().fill(Color.sbStill).frame(width: 9, height: 9)
                    }
                    .annotationTitles(.hidden)
                }
            }
            if let start = routeCoordinates.first {
                Annotation("Start", coordinate: start, anchor: .center) {
                    RouteMarker(fill: .white, stroke: .sbRed)
                }
                .annotationTitles(.hidden)
            }
            if routeCoordinates.count > 1, let end = routeCoordinates.last {
                Annotation("Finish", coordinate: end, anchor: .center) {
                    RouteMarker(fill: .sbRed, stroke: .white)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControls {}
        .environment(\.colorScheme, .dark)
        .background(Color.sbMapBackground)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) { legend }
    }

    /// Runs red, lifts blue. Without detected segments the whole route is one red line.
    @MapContentBuilder
    private func routeLines(opacity: Double) -> some MapContent {
        if routeParts.isEmpty {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(Color.sbRed.opacity(opacity), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        } else {
            ForEach(routeParts) { part in
                MapPolyline(coordinates: part.coordinates)
                    .stroke(
                        (part.activity == .lift ? Color.sbLift : Color.sbRed).opacity(opacity),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        if !routeParts.isEmpty {
            HStack(spacing: 12) {
                legendItem("RUN", .sbRed)
                legendItem("LIFT", .sbLift)
                if !stillSpots.isEmpty { legendItem("STOP", .sbStill) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55), in: Capsule())
            .padding(12)
        }
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.sb(12)).tracking(12 * 0.04).foregroundStyle(.white)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: startReplay) {
                Text("REPLAY")
                    .font(.sb(22))
                    .foregroundStyle(.sbGreyButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle(pressedBrightness: -0.05))
            .disabled(session.points.count < 2)

            Button(action: share) {
                Group {
                    if isPreparingShare {
                        ProgressView().tint(.sbGreyButtonText)
                    } else {
                        Text("SHARE").font(.sb(22))
                    }
                }
                .foregroundStyle(.sbGreyButtonText)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle(pressedBrightness: -0.05))
            .disabled(isPreparingShare)

            Button(action: export) {
                Text("EXPORT")
                    .font(.sb(22))
                    .foregroundStyle(.sbGreyButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle(pressedBrightness: -0.05))
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 106)
    }

    // MARK: - Actions

    private var summaryText: String {
        "\(placeName) · \(session.startDate.formatted(date: .abbreviated, time: .omitted)) — "
            + "\(units.distance(meters: session.distance)), top speed \(units.speed(metersPerSecond: session.maxSpeed)). "
            + "Tracked with RideLirium."
    }

    private func startReplay() {
        isReplaying = true
        replay.restart()
    }

    private func closeReplay() {
        replay.pause()
        isReplaying = false
    }

    private func share() {
        isPreparingShare = true
        Task {
            let map = await RouteSnapshot.make(coordinates: session.coordinates)
            let card = RideShareCard(
                map: map,
                placeName: placeName,
                date: session.startDate.formatted(.dateTime.day(.twoDigits).month(.abbreviated)),
                distance: String(format: "%.1f", units.distanceValue(meters: session.distance)),
                distanceUnit: units.distanceUnit,
                maxSpeed: units.speed(metersPerSecond: session.maxSpeed)
            )
            isPreparingShare = false
            if let image = card.render() {
                shareContent = ShareContent(items: [image, summaryText])
            } else {
                shareContent = ShareContent(items: [summaryText])
            }
        }
    }

    private func export() {
        let csv = TrackCSV.csv(points: session.points, metadata: SessionMetadata.load(session: session.session))
        let day = session.startDate.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideLirium-\(day)-session-\(session.session).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareContent = ShareContent(items: [url])
        } catch {
            shareContent = ShareContent(items: [csv])
        }
    }

    // MARK: - Geometry

    fileprivate static func routeRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)
        guard let first = points.first else { return .world }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for point in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        // Keep single-point or very short routes from zooming in to street level.
        let minimumSide = MKMapPointsPerMeterAtLatitude(first.coordinate.latitude) * 400
        let width = max(rect.width, minimumSide)
        let height = max(rect.height, minimumSide)
        let padded = MKMapRect(
            x: rect.midX - width * 0.65,
            y: rect.midY - height * 0.65,
            width: width * 1.3,
            height: height * 1.3
        )
        return padded
    }
}

/// Back link used by pushed screens, which hide the system navigation bar.
struct BackLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Chevron(color: .white, lineWidth: 3, size: 11, pointsLeft: true)
                Text(title)
                    .font(.sb(16))
                    .cssLineHeight(1, fontSize: 16)
            }
            .foregroundStyle(.white)
            .frame(height: 44)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .padding(.leading, -4)
        // The design reserves 34 pt; the extra 10 pt of hit area overlaps the surrounding padding.
        .padding(.vertical, -5)
        .accessibilityLabel("Back to \(title.capitalized)")
    }
}

private struct RoutePart: Identifiable {
    let id: Int
    let activity: Activity
    let coordinates: [CLLocationCoordinate2D]
}

private struct RouteMarker: View {
    let fill: Color
    let stroke: Color

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(stroke, lineWidth: 3))
            .frame(width: 12, height: 12)
    }
}

private struct ShareContent: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Renders the route on a dark map image for sharing; Map views can't be captured with ImageRenderer.
private enum RouteSnapshot {
    static func make(coordinates: [CLLocationCoordinate2D]) async -> UIImage? {
        guard !coordinates.isEmpty else { return nil }
        let options = MKMapSnapshotter.Options()
        options.mapRect = DailyStatsScreen.routeRect(for: coordinates)
        options.size = CGSize(width: 390, height: 390)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let red = UIColor(Color.sbRed)
        return UIGraphicsImageRenderer(size: options.size).image { _ in
            snapshot.image.draw(at: .zero)
            let points = coordinates.map(snapshot.point(for:))

            let route = UIBezierPath()
            route.lineWidth = 4
            route.lineCapStyle = .round
            route.lineJoinStyle = .round
            for (index, point) in points.enumerated() {
                index == 0 ? route.move(to: point) : route.addLine(to: point)
            }
            red.setStroke()
            route.stroke()

            func marker(at point: CGPoint, fill: UIColor, stroke: UIColor) {
                let circle = UIBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
                circle.lineWidth = 3
                fill.setFill()
                stroke.setStroke()
                circle.fill()
                circle.stroke()
            }
            if let first = points.first { marker(at: first, fill: .white, stroke: red) }
            if points.count > 1, let last = points.last { marker(at: last, fill: red, stroke: .white) }
        }
    }
}
