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

    private var units: Units { Units(metric: unitsMetric) }

    init(session: SessionSummary, placeName: String) {
        self.session = session
        self.placeName = placeName
        _cameraPosition = State(initialValue: .rect(Self.routeRect(for: session.coordinates)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            map
            buttons
        }
        .background(Color.white)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.hidden, for: .navigationBar)
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
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 58)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .background(Color.sbRed)
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
            MapPolyline(coordinates: session.coordinates)
                .stroke(Color.sbRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let start = session.coordinates.first {
                Annotation("Start", coordinate: start, anchor: .center) {
                    RouteMarker(fill: .white, stroke: .sbRed)
                }
                .annotationTitles(.hidden)
            }
            if session.coordinates.count > 1, let end = session.coordinates.last {
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
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 106)
    }

    // MARK: - Actions

    private var summaryText: String {
        "\(placeName) · \(session.startDate.formatted(date: .abbreviated, time: .omitted)) — "
            + "\(units.distance(meters: session.distance)), top speed \(units.speed(metersPerSecond: session.maxSpeed)). "
            + "Tracked with Snowboarder."
    }

    private func share() {
        isPreparingShare = true
        Task {
            var items: [Any] = [summaryText]
            if let image = await RouteSnapshot.make(coordinates: session.coordinates) {
                items.insert(image, at: 0)
            }
            isPreparingShare = false
            shareContent = ShareContent(items: items)
        }
    }

    private func export() {
        var csv = "timestamp,latitude,longitude,altitude_m,speed_mps\n"
        let formatter = ISO8601DateFormatter()
        for point in session.points {
            csv += "\(formatter.string(from: point.timestamp)),\(point.lat),\(point.lon),\(point.altitude),\(point.speed)\n"
        }
        let day = session.startDate.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snowboarder-\(day)-session-\(session.session).csv")
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
