//
//  SettingsScreen.swift
//  Snowoboarders
//

import SwiftUI

struct SettingsScreen: View {
    @AppStorage("unitsMetric") private var unitsMetric = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Units") {
                    Picker("System", selection: $unitsMetric) {
                        Text("Metric (km, km/h)").tag(true)
                        Text("Imperial (mi, mph)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color(hex: "FC4352"))
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsScreen()
}
