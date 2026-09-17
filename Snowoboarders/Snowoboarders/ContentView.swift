//
//  ContentView.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }

            StatsScreen()
                .tabItem { Label("Stats", systemImage: "chart.bar") }

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TrackPoint.self, inMemory: true)
}
