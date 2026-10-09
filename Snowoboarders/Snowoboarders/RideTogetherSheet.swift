//
//  RideTogetherSheet.swift
//  Snowoboarders
//

import SwiftUI
import UIKit
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins

struct RideTogetherSheet: View {
    @EnvironmentObject private var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case myCode, scan }
    @State private var mode: Mode = .myCode
    @State private var typedCode = ""
    @FocusState private var isTypingCode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let friend = friends.justJoined {
                joined(friend)
            } else {
                Text("RIDE TOGETHER")
                    .font(.sbFixed(32))
                    .foregroundStyle(.sbCharcoal)
                    .cssLineHeight(1, fontSize: 32)
                    .accessibilityAddTraits(.isHeader)

                SBSegmentedControl(
                    options: [("MY CODE", Mode.myCode), ("SCAN A CODE", Mode.scan)],
                    selection: $mode,
                    fillsWidth: true
                )
                .padding(.top, 18)

                Group {
                    switch mode {
                    case .myCode: myCode
                    case .scan: scan
                    }
                }
                .padding(.top, 22)

                if let error = friends.joinError {
                    Text(error)
                        .font(.sb(14, .semibold))
                        .foregroundStyle(.sbRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .animation(.easeOut(duration: 0.25), value: isTypingCode)
        // Typing collapses the camera box instead, so the field and JOIN stay above the keyboard.
        .ignoresSafeArea(.keyboard)
        .presentationDetents([.height(640)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task {
            await friends.loadInvite()
            friends.startHosting()
        }
        .onDisappear { friends.stopHosting() }
        .onChange(of: mode) { _, _ in friends.joinError = nil }
    }

    // MARK: - My code

    @ViewBuilder
    private var myCode: some View {
        VStack(spacing: 16) {
            Group {
                if let invite = friends.invite, let image = QRCode.image(for: invite.url.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Invite QR code")
                } else {
                    ProgressView()
                }
            }
            .frame(width: 220, height: 220)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.sbDivider, lineWidth: 1))

            if let invite = friends.invite {
                Text(Self.formatted(invite.code))
                    .font(.sbFixed(28))
                    .tracking(28 * 0.08)
                    .monospacedDigit()
                    .foregroundStyle(.sbCharcoal)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(invite.code.map(String.init).joined(separator: " "))")
            }

            Text("Let a friend scan this with their camera or in Snowboarder. Keep it on screen until you see them join.")
                .font(.sb(16, .semibold))
                .foregroundStyle(.sbSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let invite = friends.invite {
                ShareLink(
                    item: invite.url,
                    message: Text("Ride with me on Snowboarder. Code: \(Self.formatted(invite.code))")
                ) {
                    Text("SHARE INVITE")
                        .font(.sb(20))
                        .foregroundStyle(.sbGreyButtonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedBrightness: -0.05))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scan

    @ViewBuilder
    private var scan: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !isTypingCode {
                Group {
                    if QRScannerView.isAvailable {
                        QRScannerView { scanned in
                            Task { await friends.join(scanned) }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28, weight: .semibold))
                            Text("CAMERA SCANNING ISN'T AVAILABLE HERE")
                                .font(.sb(14))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.sbMapBackground)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    if friends.isJoining { ProgressView().tint(.white) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text(isTypingCode ? "ENTER A CODE" : "OR ENTER A CODE")
                .font(.sb(13))
                .tracking(13 * 0.08)
                .foregroundStyle(.sbSecondary)

            HStack(spacing: 10) {
                TextField("ABCD-2345", text: $typedCode)
                    .font(.sb(22))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($isTypingCode)
                    .onSubmit(joinTypedCode)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Color.sbLightGrey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button(action: joinTypedCode) {
                    Text("JOIN")
                        .font(.sb(20))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 56)
                        .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(friends.isJoining)
            }
        }
    }

    private func joinTypedCode() {
        isTypingCode = false
        Task { await friends.join(typedCode) }
    }

    // MARK: - Joined

    private func joined(_ friend: Friend) -> some View {
        VStack(spacing: 18) {
            Text(friend.initials)
                .font(.sbFixed(30))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color(hex: friend.avatarColor), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                .sbShadow(y: 6, blur: 18, opacity: 0.25)
                .padding(.top, 40)

            Text("YOU'RE RIDING WITH")
                .font(.sb(16))
                .tracking(16 * 0.08)
                .foregroundStyle(.sbSecondary)
            Text(friend.displayName.uppercased())
                .font(.sbFixed(32))
                .foregroundStyle(.sbCharcoal)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("LET'S RIDE")
                    .font(.sb(22))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.sbRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .sbShadow(y: 8, blur: 20, opacity: 0.3, color: .sbRed)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private static func formatted(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4))-\(code.suffix(4))" : code
    }
}

private enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Live QR scanning with VisionKit. Needs a device camera, so it's unavailable in the simulator.
private struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
