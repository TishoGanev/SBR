//
//  MapScreen.swift
//  Snowoboarders
//

import SwiftUI
import MapKit
import SwiftData

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tracker = LocationTracker()
    @StateObject private var weatherService = WeatherService()
    @AppStorage("unitsMetric") private var unitsMetric = true
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if tracker.trackCoordinates.count > 1 {
                        MapPolyline(coordinates: tracker.trackCoordinates)
                            .stroke(.sbTrack, lineWidth: 4)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .overlay(alignment: .bottom) { statsPanel }

                if let weather = weatherService.weather {
                    weatherPanel(weather)
                        .padding()
                } else if let errorMessage = weatherService.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .navigationTitle("Snowoboarders")
            .onAppear {
                tracker.configure(context: modelContext)
                tracker.requestAuthorization()
                weatherService.start(
                    location: { tracker.currentLocation },
                    unitsMetric: { unitsMetric }
                )
            }
            .onDisappear {
                weatherService.stop()
            }
            .onChange(of: unitsMetric) { _, newValue in
                weatherService.refresh(location: tracker.currentLocation, unitsMetric: newValue)
            }
            .onChange(of: tracker.hasFixedLocation) { _, hasFix in
                if hasFix {
                    weatherService.refresh(location: tracker.currentLocation, unitsMetric: unitsMetric)
                }
            }
            .onChange(of: tracker.trackCoordinates.count) { _, _ in
                guard tracker.isTracking, let location = tracker.currentLocation else { return }
                withAnimation {
                    cameraPosition = .camera(
                        MapCamera(centerCoordinate: location.coordinate, distance: 800)
                    )
                }
            }
        }
    }

    private func weatherPanel(_ weather: Weather) -> some View {
        HStack(spacing: 12) {
            Image(systemName: weather.symbolName)
                .font(.title)
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(weather.temperature.rounded()))°\(unitsMetric ? "C" : "F")")
                    .font(.title3.bold())
                    .foregroundStyle(.sbTitleText)
                Text(weather.description)
                    .font(.caption2)
                    .foregroundStyle(.sbSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Wind").font(.caption).foregroundStyle(.sbSecondaryText)
                Text("\(Int(weather.windSpeed.rounded())) \(unitsMetric ? "m/s" : "mph")")
                    .font(.subheadline.bold())
                    .foregroundStyle(.sbTitleText)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statsPanel: some View {
        VStack(spacing: 12) {
            HStack {
                stat("Distance", formatDistance(tracker.traveledDistance))
                Spacer()
                stat("Max Speed", formatSpeed(tracker.maxSpeed))
            }
            HStack {
                stat("Duration", formatDuration(tracker.elapsed))
                Spacer()
                stat("Altitude", formatAltitude(tracker.currentLocation?.altitude ?? 0))
            }
            Button(action: toggleTracking) {
                Text(tracker.isTracking ? "Stop" : "Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(tracker.isTracking ? Color.sbStop : Color.sbStart)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.sbSecondaryText)
            Text(value).font(.title3.bold()).foregroundStyle(.sbTitleText)
        }
    }

    private func toggleTracking() {
        if tracker.isTracking {
            tracker.stopTracking()
            withAnimation {
                cameraPosition = .userLocation(fallback: .automatic)
            }
        } else {
            tracker.startTracking()
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private func formatAltitude(_ meters: Double) -> String {
        unitsMetric
            ? String(format: "%.0f m", meters)
            : String(format: "%.0f ft", meters * 3.28084)
    }
}

#Preview {
    MapScreen()
        .modelContainer(for: TrackPoint.self, inMemory: true)
}
