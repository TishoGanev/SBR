//
//  ContentView.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData

enum AppTab {
    case track, stats, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tracker = LocationTracker()
    @StateObject private var weatherService = WeatherService()
    @AppStorage("userInitials") private var userInitials = "SB"

    @State private var tab: AppTab = .track
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            tabContent(.track) { TrackScreen() }
            tabContent(.stats) { StatsScreen(path: $statsPath) }
            tabContent(.settings) { SettingsScreen(path: $settingsPath) }

            FloatingTabBar(
                selection: tab,
                initials: userInitials,
                onTrack: { tab = .track },
                onStats: {
                    if tab == .stats { statsPath = NavigationPath() }
                    tab = .stats
                },
                onSettings: {
                    if tab == .settings { settingsPath = NavigationPath() }
                    tab = .settings
                }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(tracker)
        .environmentObject(weatherService)
        .preferredColorScheme(.light)
        .onAppear {
            tracker.configure(context: modelContext)
            tracker.requestAuthorization()
            weatherService.start(location: { tracker.currentLocation })
        }
        .onChange(of: tracker.hasFixedLocation) { _, hasFix in
            if hasFix { weatherService.refresh(location: tracker.currentLocation) }
        }
    }

    /// Every tab stays alive so the map camera and each navigation stack keep their state.
    private func tabContent<Content: View>(_ target: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == target ? 1 : 0)
            .allowsHitTesting(tab == target)
            .accessibilityHidden(tab != target)
    }
}

struct FloatingTabBar: View {
    let selection: AppTab
    let initials: String
    let onTrack: () -> Void
    let onStats: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            item("TRACK", systemImage: "record.circle", active: selection == .track, action: onTrack)
            item("STATS", systemImage: "chart.bar.fill", active: selection == .stats, action: onStats)
            avatar
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .sbShadow(y: 10, blur: 30, opacity: 0.3)
    }

    private func item(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.sb(16))
            }
            .foregroundStyle(Color.white.opacity(active ? 1 : 0.78))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                active ? Color.black.opacity(0.2) : .clear,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var avatar: some View {
        Button(action: onSettings) {
            Text(initials)
                .font(.sbFixed(15))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.sbCharcoal, in: Circle())
                .background {
                    if selection == .settings {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(selection == .settings ? .isSelected : [])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TrackPoint.self, inMemory: true)
}
