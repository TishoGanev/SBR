//
//  SocialShare.swift
//  Snowoboarders
//

import SwiftUI
import UIKit

/// Share card: route map on top, ride stats underneath.
struct RideShareCard: View {
    /// 4:5, the tallest ratio social feeds show uncropped.
    private static let size = CGSize(width: 360, height: 450)
    private static let mapHeight: CGFloat = 240
    private static let distanceSize: CGFloat = 76

    let map: UIImage?
    let placeName: String
    let date: String
    let distance: String
    let distanceUnit: String
    let maxSpeed: String

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let map {
                    Image(uiImage: map).resizable().scaledToFill()
                } else {
                    Color.sbMapBackground
                }
            }
            .frame(width: Self.size.width, height: Self.mapHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text("\(placeName.uppercased()) · \(date.uppercased())")
                    .font(.sb(16))
                    .tracking(16 * 0.04)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distance).font(.sbFixed(Self.distanceSize))
                    Text(distanceUnit.uppercased()).font(.sb(24))
                }

                Text("\(maxSpeed) MAX")
                    .font(.sb(24))

                Spacer(minLength: 0)

                Text("RIDELIRIUM")
                    .font(.sb(14))
                    .tracking(14 * 0.2)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.sbRed)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @MainActor func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3 // 1080 wide
        return renderer.uiImage
    }
}
