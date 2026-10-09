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
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RedTitleHeader(title: "SETTINGS")

                accountRow

                SettingsRow {
                    Text("UNITS")
                        .font(.sb(18))
                        .foregroundStyle(.sbCharcoal)
                    Spacer()
                    SBSegmentedControl(options: [("METRIC", true), ("IMPERIAL", false)], selection: $unitsMetric)
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

    @ViewBuilder
    private var accountRow: some View {
        if let user = auth.user {
            SettingsRow {
                Text(user.initials)
                    .font(.sbFixed(14))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.sbCharcoal, in: Circle())
                Text(user.displayName.uppercased())
                    .font(.sb(18))
                    .foregroundStyle(.sbCharcoal)
                    .lineLimit(1)
                Spacer()
                Button("SIGN OUT") {
                    Task { await auth.signOut() }
                }
                .font(.sb(15))
                .foregroundStyle(.sbRed)
                .buttonStyle(PressableStyle())
            }
        } else {
            SettingsRow {
                Text("ACCOUNT")
                    .font(.sb(18))
                    .foregroundStyle(.sbCharcoal)
                Spacer()
                Button {
                    auth.isShowingSignIn = true
                } label: {
                    Text("SIGN IN")
                        .font(.sb(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
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
