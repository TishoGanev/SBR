//
//  SettingsScreen.swift
//  Snowoboarders
//

import SwiftUI

enum SettingsRoute: Hashable {
    case about
}

struct SettingsScreen: View {
    @Binding var path: NavigationPath
    @AppStorage("unitsMetric") private var unitsMetric = true

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RedTitleHeader(title: "SETTINGS")

                SettingsRow {
                    Text("UNITS")
                        .font(.sb(18))
                        .foregroundStyle(.sbCharcoal)
                    Spacer()
                    UnitsControl(metric: $unitsMetric)
                }

                Button {
                    path.append(SettingsRoute.about)
                } label: {
                    SettingsRow {
                        Text("ABOUT SNOWBOARDER")
                            .font(.sb(18))
                            .foregroundStyle(.sbCharcoal)
                        Spacer()
                        Chevron()
                            .padding(.trailing, 4)
                    }
                }
                .buttonStyle(SettingsRowPressStyle())

                Spacer()
            }
            .background(Color.white)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .about: AboutScreen()
                }
            }
        }
    }
}

struct RedTitleHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.sbFixed(40))
            .foregroundStyle(.white)
            .cssLineHeight(1, fontSize: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 62)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(Color.sbRed)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 20)
            .frame(height: 72)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.sbDivider).frame(height: 1)
            }
            .contentShape(Rectangle())
    }
}

private struct SettingsRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sbLightGrey : Color.white)
    }
}

private struct UnitsControl: View {
    @Binding var metric: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("METRIC", selected: metric) { metric = true }
            segment("IMPERIAL", selected: !metric) { metric = false }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.sbCharcoal, lineWidth: 1.5)
        )
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sb(15))
                .cssLineHeight(1, fontSize: 15)
                .foregroundStyle(selected ? Color.white : Color.sbCharcoal)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(selected ? Color.sbCharcoal : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "VERSION \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                BackLink(title: "SETTINGS") { dismiss() }
                Text("ABOUT")
                    .font(.sbFixed(40))
                    .cssLineHeight(1, fontSize: 40)
                    .accessibilityAddTraits(.isHeader)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 58)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(Color.sbRed)

            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("SNOWBOARDER")
                    .font(.sb(28, .extraBold))
                    .foregroundStyle(.sbCharcoal)
                Text(version)
                    .font(.sb(13))
                    .tracking(13 * 0.08)
                    .foregroundStyle(.sbSecondary)
                Text("Track your runs, speed and altitude on the mountain.")
                    .font(.sb(16, .semibold))
                    .foregroundStyle(.sbSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)

            Spacer()
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}
