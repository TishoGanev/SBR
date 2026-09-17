//
//  StatsScreen.swift
//  Snowoboarders
//

import SwiftUI
import SwiftData
import CoreLocation

struct SessionSummary: Identifiable {
    let session: Int
    let points: [TrackPoint]

    var id: Int { session }
    var startDate: Date { points.first?.timestamp ?? Date() }
    var endDate: Date { points.last?.timestamp ?? Date() }
    var maxSpeed: Double { points.map(\.speed).max() ?? 0 }

    var distance: Double {
        var total: Double = 0
        var previous: CLLocation?
        for point in points {
            let location = CLLocation(latitude: point.lat, longitude: point.lon)
            if let prev = previous {
                total += location.distance(from: prev)
            }
            previous = location
        }
        return total
    }
}

enum StatsFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case all = "All"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: Date())
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .thisMonth:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        case .all:
            return .distantPast
        }
    }
}

struct StatsScreen: View {
    @Query(sort: \TrackPoint.timestamp) private var allPoints: [TrackPoint]
    @State private var filter: StatsFilter = .all
    @AppStorage("unitsMetric") private var unitsMetric = true

    private var sessions: [SessionSummary] {
        let filtered = allPoints.filter { $0.timestamp >= filter.startDate }
        let grouped = Dictionary(grouping: filtered, by: \.session)
        return grouped
            .map { SessionSummary(session: $0.key, points: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Filter", selection: $filter) {
                    ForEach(StatsFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color(hex: "FC4352"))
                .padding()

                if sessions.isEmpty {
                    Spacer()
                    Text("No runs yet").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(sessions) { session in
                        NavigationLink {
                            SessionDetailScreen(session: session)
                        } label: {
                            row(for: session)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Stats")
        }
    }

    private func row(for session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startDate, style: .date).font(.headline).foregroundStyle(.sbTitleText)
            HStack {
                Text(formatDistance(session.distance))
                Spacer()
                Text("Top: \(formatSpeed(session.maxSpeed))")
            }
            .font(.subheadline)
            .foregroundStyle(.sbSecondaryText)
        }
        .padding(.vertical, 4)
    }

    private func formatDistance(_ meters: Double) -> String {
        unitsMetric
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.2f mi", meters / 1609.34)
    }

    private func formatSpeed(_ metersPerSecond: Double) -> String {
        unitsMetric
            ? String(format: "%.1f km/h", metersPerSecond * 3.6)
            : String(format: "%.1f mph", metersPerSecond * 2.23694)
    }
}

#Preview {
    StatsScreen()
        .modelContainer(for: TrackPoint.self, inMemory: true)
}
