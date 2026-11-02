//
//  ContentView.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData
import UIKit

enum AppTab {
    case track, stats, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tracker = LocationTracker()
    @StateObject private var friends = FriendsStore()
    @StateObject private var watchBridge = PhoneWatchBridge()

    @State private var tab: AppTab = .track
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            tabContent(.track) { TrackScreen() }
            tabContent(.stats) { StatsScreen(path: $statsPath) }
            tabContent(.settings) { SettingsScreen(path: $settingsPath) }

            HStack(spacing: 10) {
                FloatingTabBar(
                    selection: tab,
                    onTrack: { tab = .track },
                    onStats: {
                        if tab == .stats { statsPath = NavigationPath() }
                        tab = .stats
                    }
                )
                SettingsTabButton(active: tab == .settings) { tab = .settings }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(tracker)
        .environmentObject(friends)
        .preferredColorScheme(.light)
        .onAppear {
            tracker.configure(context: modelContext)
            tracker.requestAuthorization()
            watchBridge.start(tracker: tracker)
        }
        .sheet(isPresented: $friends.isShowingRideTogether, onDismiss: {
            friends.justJoined = nil
            friends.joinError = nil
        }) {
            RideTogetherSheet()
                .environmentObject(friends)
        }
        .onChange(of: tracker.isTracking) { _, _ in updateSharing() }
        .onChange(of: friends.friends.isEmpty) { _, _ in updateSharing() }
        .onChange(of: friends.me) { _, _ in updateSharing() }
        .onChange(of: friends.isInviting) { _, _ in updateSharing() }
        .onOpenURL(perform: handle)
        .task {
            // Keep friends' positions fresh on the map even when this rider isn't recording
            // (a recording ride refreshes them along with its own heartbeat).
            while !Task.isCancelled {
                if !friends.isSharing { await friends.refresh() }
                try? await Task.sleep(for: .seconds(friends.friends.isEmpty ? 60 : 15))
            }
        }
    }

    /// Your position goes to your crew as soon as you are riding with someone, recording a ride, or waiting for
    /// someone to join your invite.
    private func updateSharing() {
        friends.setSharing(tracker.isTracking || !friends.friends.isEmpty || friends.isInviting, location: { tracker.currentLocation })
    }

    private func handle(_ url: URL) {
        guard InviteLink.isInvite(url) else { return }
        tab = .track
        // The Live Activity links here: just show the ride.
        if url.host == "ride" {
            friends.isShowingRideTogether = false
            return
        }
        friends.isShowingRideTogether = true
        if friends.me == nil {
            // The sheet asks for a name first, then joins.
            friends.pendingInvite = url.absoluteString
        } else {
            Task { await friends.join(url.absoluteString) }
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

/// Settings sits beside the tab bar as its own round glass button.
struct SettingsTabButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.sbCharcoal)
                .frame(width: 58, height: 58)
                .glassEffect(
                    active ? .regular.tint(.sbRed).interactive() : .regular.tint(Color.white.opacity(0.6)).interactive(),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sbShadow(y: 10, blur: 30, opacity: 0.18)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct FloatingTabBar: View {
    let selection: AppTab
    let onTrack: () -> Void
    let onStats: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                item("TRACK", systemImage: "record.circle", active: selection == .track, action: onTrack)
                item("STATS", systemImage: "chart.bar.fill", active: selection == .stats, action: onStats)
            }
            .padding(6)
        }
        // Tinted light so the charcoal labels read over the dark map as well as over white screens.
        .glassEffect(.regular.tint(Color.white.opacity(0.6)), in: Capsule())
        .sbShadow(y: 10, blur: 30, opacity: 0.18)
    }

    private func item(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.sb(16))
            }
            .foregroundStyle(active ? Color.white : Color.sbCharcoal)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(active ? .regular.tint(.sbRed).interactive() : .identity, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TrackPoint.self, inMemory: true)
}
