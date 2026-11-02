//
//  Sport.swift
//  Snowoboarders
//

import SwiftUI

/// What the rider rides. Shown as the glyph on their map tag and crew chip.
enum Sport: String, CaseIterable, Identifiable {
    case ski, board, bike

    static let storageKey = "sport"

    var id: String { rawValue }

    /// Label in the Settings control.
    var title: String {
        switch self {
        case .ski: "SKI"
        case .board: "BOARD"
        case .bike: "BIKE"
        }
    }

    /// What friends read under the tag preview.
    var activity: String {
        switch self {
        case .ski: "SKIING"
        case .board: "SNOWBOARDING"
        case .bike: "BIKING"
        }
    }

    var assetName: String {
        switch self {
        case .ski: "SportSki"
        case .board: "SportBoard"
        case .bike: "SportBike"
        }
    }

    /// The rider's own choice, as saved on this phone.
    static var saved: Sport {
        Sport(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .board
    }
}

/// The sport pictogram, drawn as a template so it takes the tint it is given.
struct SportGlyph: View {
    let sport: Sport
    var size: CGFloat = 20

    var body: some View {
        Image(sport.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
