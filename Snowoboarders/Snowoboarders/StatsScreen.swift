//
//  StatsScreen.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData
import CoreLocation
import Combine

struct SessionSummary: Identifiable {
    let session: Int
    let points: [TrackPoint]

    var id: Int { session }
    var startDate: Date { points.first?.timestamp ?? Date() }
    var endDate: Date { points.last?.timestamp ?? Date() }
    var maxSpeed: Double { points.map(\.speed).max() ?? 0 }
    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

    /// Stable across launches even if a deleted session's number is reused.
    var placeKey: String { "\(session)-\(Int(startDate.timeIntervalSince1970))" }

    var distance: Double {
        var total: Double = 0
        var previous: CLLocation?
        for point in points {
            let location = CLLocation(latitude: point.lat, longitude: point.lon)
            if let previous {
                total += location.distance(from: previous)
            }
            previous = location
        }
        return total
    }
}

/// Ski seasons run across New Year, so July starts the next one (e.g. Nov 2025 and Mar 2026 are both 2025/26).
struct Season: Hashable {
    let startYear: Int

    init(containing date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2000
        startYear = (components.month ?? 1) >= 7 ? year : year - 1
    }

    var label: String {
        String(format: "%d/%02d", startYear, (startYear + 1) % 100)
    }
}

enum StatsRoute: Hashable {
    case day(Int)
}

struct StatsScreen: View {
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrackPoint.timestamp) private var allPoints: [TrackPoint]
    @AppStorage("unitsMetric") private var unitsMetric = true
    @StateObject private var placeNames = PlaceNameStore()
    @State private var pendingDelete: SessionSummary?

    private var units: Units { Units(metric: unitsMetric) }

    private var sessions: [SessionSummary] {
        Dictionary(grouping: allPoints, by: \.session)
            .map { SessionSummary(session: $0.key, points: $0.value) }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        let sessions = sessions
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header(for: sessions)
                list(for: sessions)
            }
            .background(Color.white)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: StatsRoute.self) { route in
                switch route {
                case .day(let id):
                    if let session = sessions.first(where: { $0.id == id }) {
                        DailyStatsScreen(session: session, placeName: placeNames.name(for: session))
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this ride?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Ride", role: .destructive) {
                if let session = pendingDelete { delete(session) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Header

    private func header(for sessions: [SessionSummary]) -> some View {
        let season = Season(containing: sessions.first?.startDate ?? Date())
        let seasonSessions = sessions.filter { Season(containing: $0.startDate) == season }
        let days = Set(seasonSessions.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        let totalDistance = seasonSessions.reduce(0) { $0 + $1.distance }
        let topSpeed = seasonSessions.map(\.maxSpeed).max() ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            Text("\(season.label) SEASON · \(days) \(days == 1 ? "DAY" : "DAYS")")
                .font(.sb(18))
                .tracking(18 * 0.04)
                .cssLineHeight(1, fontSize: 18)

            HeroNumber(
                value: String(format: "%.0f", units.distanceValue(meters: totalDistance)),
                captionLines: [
                    "\(units.distanceUnit.uppercased()) RIDDEN",
                    "\(units.speed(metersPerSecond: topSpeed)) TOP SPEED",
                ]
            )
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 62)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .background(Color.sbRed)
    }

    // MARK: - Rows

    @ViewBuilder
    private func list(for sessions: [SessionSummary]) -> some View {
        if sessions.isEmpty {
            Text("NO RIDES YET")
                .font(.sb(18))
                .tracking(18 * 0.04)
                .foregroundStyle(.sbSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 110)
        } else {
            List(sessions) { session in
                Button {
                    path.append(StatsRoute.day(session.id))
                } label: {
                    row(for: session)
                }
                .buttonStyle(RowPressStyle())
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.white)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        pendingDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .task { placeNames.resolve(session) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 110, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 78)
        }
    }

    private func row(for session: SessionSummary) -> some View {
        HStack(spacing: 14) {
            Text(session.startDate.formatted(.dateTime.day(.twoDigits)))
                .font(.sb(40))
                .monospacedDigit()
                .foregroundStyle(.sbCharcoal)
                .cssLineHeight(1, fontSize: 40)
                .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.startDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.sb(14))
                    .foregroundStyle(.sbRed)
                    .cssLineHeight(1, fontSize: 14)
                Text(session.startDate.formatted(.dateTime.year()))
                    .font(.sb(13, .semibold))
                    .foregroundStyle(.sbSecondary)
                    .cssLineHeight(1, fontSize: 13)
            }
            .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(placeNames.name(for: session))
                    .font(.sb(18))
                    .foregroundStyle(.sbCharcoal)
                    .lineLimit(1)
                    .cssLineHeight(1.1, fontSize: 18)
                Text("\(units.distance(meters: session.distance)) · \(units.speed(metersPerSecond: session.maxSpeed))")
                    .font(.sb(14, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.sbSecondary)
                    .lineLimit(1)
                    .cssLineHeight(1.2, fontSize: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chevron()
                .padding(.trailing, 4)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 78)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.sbDivider).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func delete(_ session: SessionSummary) {
        for point in session.points {
            modelContext.delete(point)
        }
        try? modelContext.save()
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sbLightGrey : Color.white)
    }
}

/// The 88 pt headline number with its two-line caption, shared by Stats and Daily stats.
struct HeroNumber: View {
    let value: String
    let captionLines: [String]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(value)
                .font(.sbFixed(88))
                .tracking(-88 * 0.02)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .cssLineHeight(0.9, fontSize: 88)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(captionLines, id: \.self) { line in
                    Text(line)
                        .font(.sb(20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .cssLineHeight(1.25, fontSize: 20)
                }
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Resolves a resort or town name for each session's start point. Results are cached across launches.
@MainActor
final class PlaceNameStore: ObservableObject {
    @Published private var names: [String: String]

    private var queue: [(key: String, location: CLLocation)] = []
    private var attempted: Set<String> = []
    private var isResolving = false
    private let geocoder = CLGeocoder()
    private static let defaultsKey = "sessionPlaceNames"

    init() {
        names = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    func name(for session: SessionSummary) -> String {
        names[session.placeKey] ?? "Session \(session.session)"
    }

    func resolve(_ session: SessionSummary) {
        let key = session.placeKey
        guard names[key] == nil, !attempted.contains(key), let first = session.points.first else { return }
        attempted.insert(key)
        queue.append((key, CLLocation(latitude: first.lat, longitude: first.lon)))
        processQueue()
    }

    /// CLGeocoder is rate-limited, so requests run one at a time.
    private func processQueue() {
        guard !isResolving, !queue.isEmpty else { return }
        isResolving = true
        let next = queue.removeFirst()
        Task {
            let placemark = try? await geocoder.reverseGeocodeLocation(next.location).first
            if let name = placemark?.areasOfInterest?.first ?? placemark?.locality ?? placemark?.name {
                names[next.key] = name
                UserDefaults.standard.set(names, forKey: Self.defaultsKey)
            }
            isResolving = false
            processQueue()
        }
    }
}
