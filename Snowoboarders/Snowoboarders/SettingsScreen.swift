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
    @AppStorage(Sport.storageKey) private var sport = Sport.board
    @AppStorage(AutoRecordSettings.autoStartKey) private var autoStart = false
    @AppStorage(AutoRecordSettings.autoStopKey) private var autoStop = false
    @AppStorage(AutoRecordSettings.stopMinutesKey) private var stopMinutes = AutoRecordSettings.defaultStopMinutes
    @EnvironmentObject private var friends: FriendsStore
    @EnvironmentObject private var tracker: LocationTracker
    @State private var isEditingName = false
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RedTitleHeader(title: "SETTINGS")

                nameRow

                SettingsRow {
                    Text("UNITS")
                        .font(.sb(18))
                        .foregroundStyle(.sbCharcoal)
                    Spacer()
                    SBSegmentedControl(options: [("METRIC", true), ("IMPERIAL", false)], selection: $unitsMetric)
                }

                sportRow

                autoRecordRow

                Button {
                    path.append(SettingsRoute.about)
                } label: {
                    SettingsRow {
                        Text("ABOUT RIDELIRIUM")
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

    /// What the rider rides, and a preview of the tag friends see for it.
    private var sportRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("I RIDE")
                    .font(.sb(18))
                    .foregroundStyle(.sbCharcoal)
                Spacer()
                SBSegmentedControl(options: Sport.allCases.map { ($0.title, $0) }, selection: $sport)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("How friends see you")
                    .font(.sb(13, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    RiderTag(friend: previewFriend, units: Units(metric: unitsMetric), compact: false, sport: sport)
                    Text(sport.activity)
                        .font(.sb(11))
                        .tracking(11 * 0.04)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sbMapBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.sbDivider).frame(height: 1)
        }
    }

    /// Starting and stopping a recording from motion activity. Recorded points are never deleted by it.
    private var autoRecordRow: some View {
        VStack(spacing: 14) {
            Toggle("START WHEN DRIVING", isOn: $autoStart)
            Toggle("STOP WHEN IDLE", isOn: $autoStop)
            if autoStop {
                Stepper("AFTER \(stopMinutes) MIN STANDING OR WALKING", value: $stopMinutes, in: 1...30)
            }
        }
        .font(.sb(18))
        .foregroundStyle(.sbCharcoal)
        .tint(.sbRed)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.sbDivider).frame(height: 1)
        }
        .onChange(of: autoStart) { _, _ in tracker.refreshMotionMonitoring() }
    }

    /// You, in the riding state, as a friend's map would draw you.
    private var previewFriend: Friend {
        Friend(
            id: friends.me?.id ?? "preview",
            displayName: friends.me?.displayName ?? "You",
            initials: friends.me?.initials ?? "ME",
            speedKmh: 24,
            updatedAt: .now
        )
    }

    /// The name nearby riders see when you ride together. It stays on this phone.
    private var nameRow: some View {
        SettingsRow {
            Text(friends.me?.initials ?? "SB")
                .font(.sbFixed(14))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.sbCharcoal, in: Circle())
            Text((friends.me?.displayName ?? "YOUR NAME").uppercased())
                .font(.sb(18))
                .foregroundStyle(.sbCharcoal)
                .lineLimit(1)
            Spacer()
            Button(friends.me == nil ? "ADD" : "EDIT") {
                nameDraft = friends.me?.displayName ?? ""
                isEditingName = true
            }
            .font(.sb(15))
            .foregroundStyle(.sbRed)
            .buttonStyle(PressableStyle())
        }
        .alert("Your name", isPresented: $isEditingName) {
            TextField("Name", text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { friends.setName(nameDraft) }
        } message: {
            Text("Riders who join your code see this name. It isn't stored anywhere but on your phone.")
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
                Text("RIDELIRIUM")
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
