//
//  Theme.swift
//  Snowoboarders
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let sbRed = Color(hex: 0xED213D)
    static let sbCharcoal = Color(hex: 0x353535)
    static let sbSecondary = Color(hex: 0x8A8A8A)
    static let sbLightGrey = Color(hex: 0xF2F2F2)
    static let sbGreyButtonText = Color(hex: 0x4D4D4D)
    static let sbDivider = Color(hex: 0xE8E8E8)
    static let sbChevron = Color(hex: 0xBDBDBD)
    static let sbMapBackground = Color(hex: 0x141B24)
    static let sbSun = Color(hex: 0xFFB340)
    static let sbUserDot = Color(hex: 0x1A7CFF)
}

extension ShapeStyle where Self == Color {
    static var sbRed: Color { .sbRed }
    static var sbCharcoal: Color { .sbCharcoal }
    static var sbSecondary: Color { .sbSecondary }
    static var sbLightGrey: Color { .sbLightGrey }
    static var sbGreyButtonText: Color { .sbGreyButtonText }
    static var sbDivider: Color { .sbDivider }
    static var sbChevron: Color { .sbChevron }
}

enum SBWeight {
    case semibold, bold, extraBold

    var fontName: String {
        switch self {
        case .semibold: "OpenSans-CondensedSemiBold"
        case .bold: "OpenSans-CondensedBold"
        case .extraBold: "OpenSans-CondensedExtraBold"
        }
    }
}

extension Font {
    static func sb(_ size: CGFloat, _ weight: SBWeight = .bold) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Hero numbers are laid out against fixed card and header heights, so they don't scale with Dynamic Type.
    static func sbFixed(_ size: CGFloat, _ weight: SBWeight = .extraBold) -> Font {
        .custom(weight.fontName, fixedSize: size)
    }
}

extension View {
    /// CSS box-shadow `0 y blur rgba(0,0,0,opacity)`; SwiftUI's radius is roughly half the CSS blur.
    func sbShadow(y: CGFloat, blur: CGFloat, opacity: Double, color: Color = .black) -> some View {
        shadow(color: color.opacity(opacity), radius: blur / 2, x: 0, y: y)
    }

    /// Matches a CSS `line-height` (as a multiple of font size). Open Sans' natural line box is 1.362 em,
    /// so the design's tight 0.9–1.05 line-heights need negative vertical padding.
    func cssLineHeight(_ multiple: CGFloat, fontSize: CGFloat) -> some View {
        padding(.vertical, (multiple - 1.362) * fontSize / 2)
    }
}

/// Dims the label while pressed, like the prototype's `filter: brightness(...)` active state.
struct PressableStyle: ButtonStyle {
    var pressedBrightness: Double = -0.08

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? pressedBrightness : 0)
    }
}

/// Right-pointing chevron drawn like the design's rotated two-border square.
struct Chevron: View {
    var color: Color = .sbChevron
    var lineWidth: CGFloat = 2.5
    var size: CGFloat = 10
    var pointsLeft = false

    var body: some View {
        Path { path in
            let arm = size * 0.7
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: arm, y: arm))
            path.addLine(to: CGPoint(x: 0, y: arm * 2))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
        .frame(width: size * 0.7, height: size * 1.4)
        .scaleEffect(x: pointsLeft ? -1 : 1)
    }
}

/// Converts and formats values for the selected unit system.
struct Units {
    let metric: Bool

    private static let kmPerMile = 0.621
    private static let feetPerMeter = 3.281

    func distanceValue(meters: Double) -> Double {
        let km = meters / 1000
        return metric ? km : km * Self.kmPerMile
    }

    func speedValue(metersPerSecond: Double) -> Double {
        let kmh = max(metersPerSecond, 0) * 3.6
        return metric ? kmh : kmh * Self.kmPerMile
    }

    func altitudeValue(meters: Double) -> Double {
        metric ? meters : meters * Self.feetPerMeter
    }

    func temperatureValue(celsius: Double) -> Double {
        metric ? celsius : celsius * 9 / 5 + 32
    }

    var distanceUnit: String { metric ? "km" : "mi" }
    var speedUnit: String { metric ? "KM/H" : "MPH" }
    var altitudeUnit: String { metric ? "m" : "ft" }
    var temperatureUnit: String { metric ? "C" : "F" }

    func distance(meters: Double) -> String {
        String(format: "%.2f %@", distanceValue(meters: meters), distanceUnit)
    }

    func speed(metersPerSecond: Double) -> String {
        String(format: "%.1f %@", speedValue(metersPerSecond: metersPerSecond), speedUnit)
    }

    func altitude(meters: Double) -> String {
        "\(Int(altitudeValue(meters: meters).rounded())) \(altitudeUnit)"
    }

    func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
