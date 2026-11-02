//
//  RiderTag.swift
//  Snowoboarders
//

import SwiftUI

/// A friend on the map: a name tag with their sport glyph in their colour and their live status. Riding shows their
/// speed, stopped says so, and a rider who hasn't sent a position for two minutes goes grey with "last seen".
struct RiderTag: View {
    let friend: Friend
    let units: Units
    let compact: Bool
    var sport: Sport = .board

    private enum Look { case riding, stopped, lastSeen }

    static let liveWindow: TimeInterval = 120
    private static let movingKmh = 2.0

    private var color: Color { Color(hex: friend.avatarColor) }

    var body: some View {
        // The status ages on its own, so re-read the clock now and then.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let age = max(0, context.date.timeIntervalSince(friend.updatedAt ?? context.date))
            let look: Look = age > Self.liveWindow ? .lastSeen : (friend.speedKmh ?? 0) > Self.movingKmh ? .riding : .stopped
            if compact {
                dot(look)
            } else {
                tag(look, age: age)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(friend.displayName)
    }

    // MARK: Pieces

    private func tag(_ look: Look, age: TimeInterval) -> some View {
        let fill = look == .lastSeen ? Color(hex: 0xC9CDD3) : Color.white
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                coin(look)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.sbFixed(13, .bold))
                        .foregroundStyle(look == .lastSeen ? Color(hex: 0x4A515B) : .sbCharcoal)
                        .lineLimit(1)
                        .cssLineHeight(1, fontSize: 13)
                    Text(status(look, age: age))
                        .font(.sbFixed(10, .bold))
                        .tracking(10 * 0.03)
                        .foregroundStyle(statusColor(look))
                        .lineLimit(1)
                        .cssLineHeight(1, fontSize: 10)
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(.leading, 4)
            .padding(.vertical, 4)
            .padding(.trailing, 12)
            .background(fill, in: Capsule())
            .shadow(color: .black.opacity(0.45), radius: 6, y: 4)

            TagPointer()
                .fill(fill)
                .frame(width: 12, height: 7)
        }
    }

    private func coin(_ look: Look) -> some View {
        ZStack {
            if look == .riding {
                // Halo: a 4 pt ring around the coin.
                Circle().fill(color.opacity(0.3)).frame(width: 38, height: 38)
            }
            Circle()
                .fill(coinFill(look))
                .frame(width: 30, height: 30)
                .overlay {
                    if look == .stopped { Circle().strokeBorder(color, lineWidth: 2.5) }
                }
            SportGlyph(sport: sport, size: 20)
                .foregroundStyle(glyphTint(look))
        }
        .frame(width: 30, height: 30)
    }

    /// Far out, the tag collapses to a dot in the rider's colour.
    private func dot(_ look: Look) -> some View {
        Circle()
            .fill(look == .lastSeen ? Color(hex: 0x8C939D) : color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            .padding(8)
    }

    // MARK: State

    private func coinFill(_ look: Look) -> Color {
        switch look {
        case .riding: color
        case .stopped: .white
        case .lastSeen: Color(hex: 0x8C939D)
        }
    }

    private func glyphTint(_ look: Look) -> Color {
        switch look {
        case .riding: .white
        case .stopped: color
        case .lastSeen: Color(hex: 0xE4E7EB)
        }
    }

    private func statusColor(_ look: Look) -> Color {
        switch look {
        case .riding: color
        case .stopped: .sbSecondary
        case .lastSeen: Color(hex: 0x6A717B)
        }
    }

    private func status(_ look: Look, age: TimeInterval) -> String {
        switch look {
        case .riding:
            let value = units.speedValue(metersPerSecond: (friend.speedKmh ?? 0) / 3.6)
            return "\(Int(value.rounded())) \(units.speedUnit)"
        case .stopped:
            return "STOPPED"
        case .lastSeen:
            let minutes = Int(age / 60)
            return minutes < 60 ? "LAST SEEN \(minutes)M AGO" : "LAST SEEN \(minutes / 60)H AGO"
        }
    }
}

/// The 12 × 7 pointer under a tag; its tip is the rider's position.
struct TagPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
