//
//  TrackScreen.swift
//  Snowoboarders
//

import SwiftUI
import MapKit

struct TrackScreen: View {
    @EnvironmentObject private var tracker: LocationTracker
    @EnvironmentObject private var weatherService: WeatherService
    @AppStorage("unitsMetric") private var unitsMetric = true

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var lastCamera: MapCamera?
    @State private var follow = false
    @State private var ignoreUserCameraUntil: Date = .distantPast

    private var units: Units { Units(metric: unitsMetric) }
    private static let followCamera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        ZStack {
            map

            VStack(spacing: 0) {
                topChips
                    .padding(.top, 62)
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
                bottomStack
                    .padding(.horizontal, 12)
                    .padding(.bottom, 104)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if tracker.trackCoordinates.count > 1 {
                MapPolyline(coordinates: tracker.trackCoordinates)
                    .stroke(Color.sbRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let location = tracker.currentLocation {
                Annotation("", coordinate: location.coordinate, anchor: .center) {
                    UserDot()
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControls {}
        .environment(\.colorScheme, .dark)
        .background(Color.sbMapBackground)
        .onMapCameraChange(frequency: .onEnd) { context in
            lastCamera = context.camera
        }
        .onChange(of: cameraPosition) { _, position in
            // A tap on an overlaid button also reaches MapKit, which drops user tracking a moment
            // after we asked for it. Re-assert our own camera move instead of treating it as the user's.
            if position.positionedByUser, Date() < ignoreUserCameraUntil {
                cameraPosition = Self.followCamera
                return
            }
            // Programmatic follow keeps `followsUserLocation`; MapKit replaces it when the user moves the map.
            if !position.followsUserLocation { follow = false }
        }
        // Gestures are the reliable signal that the user took over, so follow never resumes by itself.
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in userMovedMap() })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in userMovedMap() })
    }

    private func userMovedMap() {
        guard follow else { return }
        stopFollowing()
    }

    // MARK: - Top chips

    @ViewBuilder
    private var topChips: some View {
        if let weather = weatherService.weather {
            WeatherChip(weather: weather, units: units)
        } else if let errorMessage = weatherService.errorMessage {
            #if DEBUG
            Text(errorMessage)
                .font(.sb(12))
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sbCharcoal, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            #endif
        }
    }

    // MARK: - Bottom stack

    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            mapButton
            statsCard
        }
    }

    @ViewBuilder
    private var mapButton: some View {
        if !tracker.isTracking {
            Button(action: recenter) {
                LocationPin()
                    .frame(width: 52, height: 52)
                    .background(Color.white, in: Circle())
                    .sbShadow(y: 6, blur: 18, opacity: 0.35)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Re-centre map")
        } else if follow {
            followPill(title: "FOLLOWING", filled: true) { stopFollowing() }
        } else {
            followPill(title: "FOLLOW ME", filled: false) { startFollowing() }
        }
    }

    private func followPill(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                NavigationArrow(filled: filled)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.sb(17))
                    .cssLineHeight(1, fontSize: 17)
            }
            .foregroundStyle(filled ? Color.white : Color.sbRed)
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .frame(height: 52)
            .background(filled ? Color.sbRed : Color.white, in: Capsule())
            .sbShadow(y: 6, blur: 18, opacity: 0.35)
        }
        .buttonStyle(PressableStyle())
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracker.isTracking {
                liveHeader
                    .padding(.bottom, 14)
            }

            HStack(alignment: .top, spacing: 12) {
                statColumn("DISTANCE", units.distance(meters: tracker.traveledDistance))
                statColumn("MAX SPEED", maxSpeedValue)
                statColumn("ALTITUDE", altitudeValue)
            }
            .padding(.bottom, 18)

            buttons

            if !tracker.isTracking {
                Text(gpsStatus)
                    .font(.sb(12))
                    .tracking(12 * 0.08)
                    .foregroundStyle(.sbSecondary)
                    .cssLineHeight(1, fontSize: 12)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sbShadow(y: 14, blur: 40, opacity: 0.45)
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("\(tracker.isPaused ? "PAUSED" : "RECORDING") · \(units.duration(tracker.elapsed))")
                    .font(.sb(14))
                    .tracking(14 * 0.04)
                    .monospacedDigit()
                    .cssLineHeight(1, fontSize: 14)
            }
            .foregroundStyle(.sbRed)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(String(format: "%.0f", tracker.isPaused ? 0 : units.speedValue(metersPerSecond: tracker.currentSpeed)))
                    .font(.sbFixed(80))
                    .tracking(-80 * 0.02)
                    .monospacedDigit()
                    .foregroundStyle(.sbCharcoal)
                    .cssLineHeight(0.9, fontSize: 80)
                Text(units.speedUnit)
                    .font(.sb(20))
                    .foregroundStyle(.sbSecondary)
            }
        }
    }

    private func statColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.sb(13))
                .tracking(13 * 0.04)
                .foregroundStyle(.sbSecondary)
                .cssLineHeight(1, fontSize: 13)
            Text(value)
                .font(.sbFixed(28))
                .monospacedDigit()
                .foregroundStyle(.sbCharcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .cssLineHeight(1.05, fontSize: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        if tracker.isTracking {
            GeometryReader { proxy in
                let available = proxy.size.width - 10
                HStack(spacing: 10) {
                    Button(action: togglePause) {
                        Text(tracker.isPaused ? "RESUME" : "PAUSE")
                            .font(.sb(22))
                            .foregroundStyle(.sbGreyButtonText)
                            .frame(width: available / 2.4, height: 68)
                            .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(pressedBrightness: -0.05))

                    Button(action: stopTracking) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 16, height: 16)
                            Text("STOP").font(.sb(22))
                        }
                        .foregroundStyle(.white)
                        .frame(width: available * 1.4 / 2.4, height: 68)
                        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .sbShadow(y: 8, blur: 20, opacity: 0.3, color: .sbRed)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .frame(height: 68)
        } else {
            Button(action: startTracking) {
                HStack(spacing: 12) {
                    Circle().fill(.white).frame(width: 16, height: 16)
                    Text("START TRACKING").font(.sb(22))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .sbShadow(y: 8, blur: 20, opacity: 0.3, color: .sbRed)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Values

    private var maxSpeedValue: String {
        let value = String(format: "%.1f", units.speedValue(metersPerSecond: tracker.maxSpeed))
        return unitsMetric ? value : "\(value) mph"
    }

    private var altitudeValue: String {
        guard let altitude = tracker.currentLocation?.altitude else { return "--" }
        return units.altitude(meters: altitude)
    }

    private var gpsStatus: String {
        guard let location = tracker.currentLocation, location.horizontalAccuracy >= 0 else {
            return "SEARCHING FOR GPS…"
        }
        let accuracy = Int(units.altitudeValue(meters: location.horizontalAccuracy).rounded())
        let unit = units.altitudeUnit.uppercased()
        return location.horizontalAccuracy <= 20
            ? "GPS LOCKED · ±\(accuracy) \(unit)"
            : "WEAK GPS · ±\(accuracy) \(unit)"
    }

    // MARK: - Actions

    private func startTracking() {
        tracker.startTracking()
        startFollowing()
    }

    private func stopTracking() {
        tracker.stopTracking()
        follow = false
    }

    private func togglePause() {
        if tracker.isPaused {
            tracker.resumeTracking()
        } else {
            tracker.pauseTracking()
        }
    }

    private func startFollowing() {
        follow = true
        moveCameraToUser()
    }

    private func stopFollowing() {
        follow = false
        ignoreUserCameraUntil = .distantPast
        if let lastCamera {
            cameraPosition = .camera(lastCamera)
        }
    }

    private func recenter() {
        moveCameraToUser()
    }

    private func moveCameraToUser() {
        ignoreUserCameraUntil = Date().addingTimeInterval(0.6)
        withAnimation(.easeOut(duration: 0.45)) {
            cameraPosition = Self.followCamera
        }
    }
}

// MARK: - Components

private struct WeatherChip: View {
    let weather: Weather
    let units: Units

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.1f°%@", units.temperatureValue(celsius: weather.temperatureCelsius), units.temperatureUnit))
                    .font(.sb(22, .extraBold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .cssLineHeight(1, fontSize: 22)
                Text("\(weather.description) · WIND \(wind)")
                    .font(.sb(13))
                    .tracking(13 * 0.04)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .cssLineHeight(1, fontSize: 13)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sbShadow(y: 6, blur: 18, opacity: 0.35)
        .accessibilityElement(children: .combine)
    }

    private var wind: String {
        let kmh = weather.windMetersPerSecond * 3.6
        let value = units.metric ? kmh : kmh * 0.621
        return "\(Int(value.rounded())) \(units.metric ? "KM/H" : "MPH")"
    }

    @ViewBuilder
    private var icon: some View {
        if weather.isClearDay {
            Circle()
                .fill(Color.sbSun)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: weather.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
        }
    }
}

private struct UserDot: View {
    var body: some View {
        Circle()
            .fill(Color.sbUserDot)
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(Color(red: 46 / 255, green: 110 / 255, blue: 200 / 255).opacity(0.22))
                    .padding(-14)
            )
    }
}

private struct PulsingDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color.sbRed)
            .frame(width: 9, height: 9)
            .opacity(dimmed ? 0.25 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// Teardrop pin from the design: an 18 pt square with three round corners, rotated −45°, with a white centre.
private struct LocationPin: View {
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 9, topTrailingRadius: 9)
            .fill(Color.sbCharcoal)
            .frame(width: 18, height: 18)
            .overlay(Circle().fill(.white).frame(width: 6, height: 6))
            .rotationEffect(.degrees(-45))
    }
}

private struct NavigationArrow: View {
    let filled: Bool

    var body: some View {
        let shape = ArrowShape()
        if filled {
            shape.fill(.white)
        } else {
            shape.stroke(Color.sbRed, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            let sx = rect.width / 20, sy = rect.height / 20
            var path = Path()
            path.move(to: CGPoint(x: 10 * sx, y: 2 * sy))
            path.addLine(to: CGPoint(x: 17 * sx, y: 17 * sy))
            path.addLine(to: CGPoint(x: 10 * sx, y: 13.5 * sy))
            path.addLine(to: CGPoint(x: 3 * sx, y: 17 * sy))
            path.closeSubpath()
            return path
        }
    }
}
