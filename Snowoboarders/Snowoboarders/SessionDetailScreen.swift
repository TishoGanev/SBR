//
//  SessionDetailScreen.swift
//  Snowoboarders
//

import SwiftUI
import MapKit

struct SessionDetailScreen: View {
    let session: SessionSummary
    @AppStorage("unitsMetric") private var unitsMetric = true
    @State private var cameraPosition: MapCameraPosition

    init(session: SessionSummary) {
        self.session = session
        let coordinates = session.points.map(\.coordinate)
        let rect = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
        _cameraPosition = State(initialValue: .rect(rect))
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                MapPolyline(coordinates: session.points.map(\.coordinate))
                    .stroke(.sbTrack, lineWidth: 4)
            }
            .frame(height: 300)

            List {
                Section {
                    detailRow("Date", session.startDate.formatted(date: .abbreviated, time: .omitted))
                    detailRow("Start", session.startDate.formatted(date: .omitted, time: .shortened))
                    detailRow("End", session.endDate.formatted(date: .omitted, time: .shortened))
                    detailRow("Distance", formatDistance(session.distance))
                    detailRow("Top Speed", formatSpeed(session.maxSpeed), valueColor: Color(hex: "ED213D"))
                }
            }
        }
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, _ value: String, valueColor: Color = .sbTitleText) -> some View {
        HStack {
            Text(title).foregroundStyle(.sbSecondaryText)
            Spacer()
            Text(value).bold().foregroundStyle(valueColor)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        unitsMetric
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.2f mi", meters / 1609.34)
    }

    private func formatSpeed(_ metersPerSecond: Double) -> String {
        unitsMetric
            ? String(format: "%.1f km/h", metersPerSecond * 3.6)
            : String(format: "%.1f mph", metersPerSecond * 2.23694)
    }
}
