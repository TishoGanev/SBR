//
//  InsightsSheet.swift
//  Snowoboarders
//

import SwiftUI

/// Written insights from the on-device model (when available) above the numbers they are based on.
struct InsightsSheet: View {
    @ObservedObject var model: RideInsightsModel
    let facts: RideInsightFacts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("INSIGHTS")
                    .font(.sb(24, .extraBold))
                    .foregroundStyle(.sbCharcoal)

                aiSection

                VStack(alignment: .leading, spacing: 10) {
                    Text("THE NUMBERS")
                        .font(.sb(13))
                        .tracking(13 * 0.04)
                        .foregroundStyle(.sbSecondary)
                    ForEach(facts.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Color.sbRed).frame(width: 7, height: 7).padding(.top, 8)
                            Text(bullet).font(.sb(18, .semibold)).foregroundStyle(.sbCharcoal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.white)
        .task { await model.generate(facts) }
    }

    @ViewBuilder
    private var aiSection: some View {
        switch model.state {
        case .idle, .generating:
            HStack(spacing: 10) {
                ProgressView()
                Text("Writing insights on your iPhone…")
                    .font(.sb(16, .semibold))
                    .foregroundStyle(.sbSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        case .ready(let summary):
            VStack(alignment: .leading, spacing: 12) {
                Label("ON-DEVICE AI", systemImage: "sparkles")
                    .font(.sb(13))
                    .tracking(13 * 0.04)
                    .foregroundStyle(.white.opacity(0.85))
                Text(summary.headline)
                    .font(.sb(26, .extraBold))
                    .foregroundStyle(.white)
                ForEach(summary.observations, id: \.self) { line in
                    Text("• \(line)").font(.sb(17, .semibold)).foregroundStyle(.white)
                }
                Text("TIP: \(summary.tip)")
                    .font(.sb(17))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                Button("WRITE AGAIN") { Task { await model.regenerate(facts) } }
                    .font(.sb(14))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

        case .unavailable(let message), .failed(let message):
            Text(message)
                .font(.sb(16, .semibold))
                .foregroundStyle(.sbSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
