//
//  TrackScreen.swift
//  Snowoboarders
//

import SwiftUI
import MapKit

struct TrackScreen: View {
    /// The profile button lives in the top bar now, so the Track screen asks to open Settings.
    @EnvironmentObject private var tracker: LocationTracker
    @EnvironmentObject private var friends: FriendsStore
    @AppStorage("unitsMetric") private var unitsMetric = true

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var lastCamera: MapCamera?
    @State private var follow = false
    @State private var showingEveryone = false
    @State private var cardExpanded = false
    @State private var ignoreUserCameraUntil: Date = .distantPast

    private var units: Units { Units(metric: unitsMetric) }
    private static let followCamera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                map

                VStack(spacing: 0) {
                    topChips
                        .padding(.top, proxy.safeAreaInsets.top + 4)
                        .padding(.horizontal, 14)
                    Spacer(minLength: 0)
                    bottomStack
                        .padding(.horizontal, 12)
                        .padding(.bottom, 104)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if tracker.trackCoordinates.count > 1 {
                MapPolyline(coordinates: tracker.trackCoordinates)
                    .stroke(Color.sbRed, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            // Riders sit above your track and, being drawn first, below your own dot; the bottom tip of each tag is their position.
            ForEach(sharedFriends) { friend in
                if let coordinate = friend.coordinate {
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        RiderTag(friend: friend, units: units, compact: compactMarkers)
                            .onTapGesture { centerOn(friend) }
                    }
                    .annotationTitles(.hidden)
                }
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
        showingEveryone = false
        guard follow else { return }
        stopFollowing()
    }

    // MARK: - Top chips

    private var topChips: some View {
        HStack(spacing: 10) {
            Button { friends.isShowingRideTogether = true } label: {
                CrewPill(friends: friends.friends)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Bottom stack

    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if !sharedFriends.isEmpty {
                showEveryoneButton
            }
            mapButton
            card
        }
    }

    @ViewBuilder
    private var mapButton: some View {
        if !tracker.isTracking {
            Button(action: recenter) {
                LocationPin()
                    .frame(width: 48, height: 48)
                    .background(Color.white, in: Circle())
                    .sbShadow(y: 4, blur: 14, opacity: 0.35)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Re-centre map")
        } else {
            Button { follow ? stopFollowing() : startFollowing() } label: {
                NavigationArrow(filled: follow)
                    .frame(width: 20, height: 20)
                    .frame(width: 48, height: 48)
                    .background(follow ? Color.sbRed : Color.white, in: Circle())
                    .sbShadow(y: 4, blur: 14, opacity: 0.35)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(follow ? "Stop following" : "Follow me")
            .accessibilityAddTraits(follow ? .isSelected : [])
        }
    }

    /// While recording, the compact card keeps the map visible; the grabber opens the full one.
    @ViewBuilder
    private var card: some View {
        if tracker.isTracking && !cardExpanded {
            compactCard
        } else {
            statsCard
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color(hex: 0xD6D6D6))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().inset(by: -20))
            .onTapGesture { setCardExpanded(!cardExpanded) }
            .gesture(
                DragGesture(minimumDistance: 8).onEnded { value in
                    if value.translation.height < -16 { setCardExpanded(true) }
                    if value.translation.height > 16 { setCardExpanded(false) }
                }
            )
            .accessibilityLabel(cardExpanded ? "Show less" : "Show more")
            .accessibilityAddTraits(.isButton)
    }

    private func setCardExpanded(_ expanded: Bool) {
        withAnimation(.easeOut(duration: 0.25)) { cardExpanded = expanded }
    }

    private var compactCard: some View {
        VStack(spacing: 10) {
            grabber

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        PulsingDot(size: 7, pulses: !tracker.isPaused)
                        Text(tracker.isPaused ? "PAUSED" : "RECORDING · \(units.duration(tracker.elapsed))")
                            .font(.sb(12))
                            .tracking(12 * 0.04)
                            .monospacedDigit()
                            .cssLineHeight(1, fontSize: 12)
                    }
                    .foregroundStyle(.sbRed)

                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(String(format: "%.0f", tracker.isPaused ? 0 : units.speedValue(metersPerSecond: tracker.currentSpeed)))
                            .font(.sbFixed(44))
                            .monospacedDigit()
                            .foregroundStyle(.sbCharcoal)
                            .cssLineHeight(1, fontSize: 44)
                        Text(units.speedUnit)
                            .font(.sb(15))
                            .foregroundStyle(.sbSecondary)
                    }
                }
                Spacer(minLength: 0)

                Button(action: togglePause) {
                    Image(systemName: tracker.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.sbGreyButtonText)
                        .frame(width: 52, height: 52)
                        .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedBrightness: -0.05))
                .accessibilityLabel(tracker.isPaused ? "Resume" : "Pause")

                Button(action: stopTracking) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 13, height: 13)
                        Text("STOP").font(.sb(18))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .sbShadow(y: 6, blur: 16, opacity: 0.3, color: .sbRed)
                }
                .buttonStyle(PressableStyle())
            }

            VStack(spacing: 10) {
                Rectangle().fill(Color(hex: 0xEFEFEF)).frame(height: 1)
                HStack(alignment: .top, spacing: 12) {
                    compactStat("DISTANCE", units.distance(meters: tracker.traveledDistance))
                    compactStat("MAX SPEED", maxSpeedValue)
                    compactStat("ALTITUDE", altitudeValue)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sbShadow(y: 14, blur: 40, opacity: 0.45)
    }

    private func compactStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sb(11))
                .foregroundStyle(.sbSecondary)
                .cssLineHeight(1, fontSize: 11)
            Text(value)
                .font(.sbFixed(20))
                .monospacedDigit()
                .foregroundStyle(.sbCharcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .cssLineHeight(1.05, fontSize: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tracker.isTracking {
                grabber
                    .padding(.bottom, 12)
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
        .padding(.top, tracker.isTracking ? 8 : 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sbShadow(y: 14, blur: 40, opacity: 0.45)
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("\(tracker.isPaused ? "PAUSED" : "RECORDING") · \(units.duration(tracker.elapsed))\(tracker.isPaused ? "" : " · " + activityLabel)")
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

    private var activityLabel: String {
        switch tracker.activity {
        case .run: "RIDING"
        case .lift: "LIFT"
        case .still: "STOPPED"
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
        cardExpanded = false
    }

    private func togglePause() {
        if tracker.isPaused {
            tracker.resumeTracking()
        } else {
            tracker.pauseTracking()
        }
    }

    /// Friends who are riding and sharing a position, so they can be drawn on the map.
    private var sharedFriends: [Friend] {
        friends.friends.filter { $0.coordinate != nil }
    }

    /// Zoomed far out, tags would pile up, so each rider becomes a small coloured dot.
    private var compactMarkers: Bool {
        (lastCamera?.distance ?? 0) > 8000
    }

    /// Centres the map on a rider without turning on Follow.
    private func centerOn(_ friend: Friend) {
        guard let coordinate = friend.coordinate else { return }
        follow = false
        showingEveryone = false
        ignoreUserCameraUntil = Date().addingTimeInterval(0.6)
        withAnimation(.easeOut(duration: 0.45)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: coordinate,
                distance: lastCamera?.distance ?? 1500,
                heading: lastCamera?.heading ?? 0,
                pitch: lastCamera?.pitch ?? 0
            ))
        }
    }

    private var showEveryoneButton: some View {
        Button(action: showEveryone) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(showingEveryone ? Color.white : Color.sbCharcoal)
                .frame(width: 48, height: 48)
                .background(showingEveryone ? Color.sbCharcoal : Color.white, in: Circle())
                .sbShadow(y: 4, blur: 14, opacity: 0.35)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Show everyone on the map")
        .accessibilityAddTraits(showingEveryone ? .isSelected : [])
    }

    /// Zooms out to fit you and every friend who is sharing a position, keeping them clear of the stats card.
    private func showEveryone() {
        var points = sharedFriends.compactMap(\.coordinate)
        if let here = tracker.currentLocation?.coordinate { points.append(here) }
        guard let first = points.first else { return }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        // Room around the riders (at least about 400 m), and extra below so the stats card doesn't cover them.
        let latSpan = max((maxLat - minLat) * 1.5, 0.004)
        let lonSpan = max((maxLon - minLon) * 1.5, 0.004)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2 - latSpan * 0.2,
            longitude: (minLon + maxLon) / 2
        )
        follow = false
        showingEveryone = true
        ignoreUserCameraUntil = Date().addingTimeInterval(0.6)
        withAnimation(.easeOut(duration: 0.45)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latSpan * 1.4, longitudeDelta: lonSpan)
            ))
        }
    }

    private func startFollowing() {
        follow = true
        showingEveryone = false
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
        showingEveryone = false
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

/// Slim bar along the top: invites you to ride with someone, or shows your crew and who is on the map.
private struct CrewPill: View {
    let friends: [Friend]

    private static let offlineGrey = Color(hex: 0x8C939D)

    var body: some View {
        // Who counts as online ages on its own, so re-read the clock now and then.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            content(now: context.date)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: Capsule())
        .sbShadow(y: 6, blur: 18, opacity: 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(friends.isEmpty ? "Ride with someone" : "Your crew")
    }

    private func isLive(_ friend: Friend, now: Date) -> Bool {
        friend.coordinate != nil && now.timeIntervalSince(friend.updatedAt ?? .distantPast) <= RiderTag.liveWindow
    }

    private func content(now: Date) -> some View {
        let live = friends.filter { isLive($0, now: now) }
        let ordered = live + friends.filter { !isLive($0, now: now) }
        let offline = friends.count - live.count

        return HStack(spacing: 12) {
            if friends.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.sbRed)
                    .padding(.leading, 8)
                Text("RIDE WITH SOMEONE")
                    .font(.sb(16, .extraBold))
                    .foregroundStyle(.sbCharcoal)
                    .lineLimit(1)
            } else {
                HStack(spacing: -10) {
                    ForEach(Array(ordered.prefix(3))) { friend in
                        SportGlyph(sport: .board, size: 18)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(isLive(friend, now: now) ? Color(hex: friend.avatarColor) : Self.offlineGrey, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(ordered))
                        .font(.sb(16, .extraBold))
                        .foregroundStyle(.sbCharcoal)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .cssLineHeight(1, fontSize: 16)
                    Text(subtitle(online: live.count, offline: offline))
                        .font(.sb(11))
                        .tracking(11 * 0.04)
                        .foregroundStyle(.sbSecondary)
                        .lineLimit(1)
                        .cssLineHeight(1, fontSize: 11)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.sbChevron)
        }
    }

    private func title(_ ordered: [Friend]) -> String {
        let first = ordered[0].displayName.uppercased()
        return ordered.count > 1 ? "RIDING WITH \(first) +\(ordered.count - 1)" : "RIDING WITH \(first)"
    }

    private func subtitle(online: Int, offline: Int) -> String {
        offline > 0 ? "\(online) ON THE MAP · \(offline) OFFLINE" : "\(online) ON THE MAP"
    }
}

struct UserDot: View {
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
    var size: CGFloat = 9
    var pulses = true
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color.sbRed)
            .frame(width: size, height: size)
            .opacity(dimmed && pulses ? 0.25 : 1)
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
