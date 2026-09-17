//
//  Color+Snowboarder.swift
//  Snowoboarders
//

import SwiftUI

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }

    static let sbTrack = Color(hex: "EC3A51")
    static let sbStop = Color(hex: "FC424E")
    static let sbStart = Color(hex: "48DE93")
    static let sbTitleText = Color(hex: "363636")
    static let sbSecondaryText = Color(hex: "B4B4B4")
    static let sbBorder = Color(hex: "E6E6E6")
}

extension ShapeStyle where Self == Color {
    static var sbTrack: Color { Color.sbTrack }
    static var sbStop: Color { Color.sbStop }
    static var sbStart: Color { Color.sbStart }
    static var sbTitleText: Color { Color.sbTitleText }
    static var sbSecondaryText: Color { Color.sbSecondaryText }
    static var sbBorder: Color { Color.sbBorder }
}
