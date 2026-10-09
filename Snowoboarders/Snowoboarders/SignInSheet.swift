//
//  SignInSheet.swift
//  Snowoboarders
//

import SwiftUI
import AuthenticationServices

struct SignInSheet: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("JOIN YOUR CREW")
                .font(.sbFixed(32))
                .foregroundStyle(.sbCharcoal)
                .cssLineHeight(1, fontSize: 32)
                .accessibilityAddTraits(.isHeader)

            Text("Sign in to see your friends on the mountain, share rides and ride together.")
                .font(.sb(17, .semibold))
                .foregroundStyle(.sbSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 12) {
                Button(action: auth.signInWithFacebook) {
                    HStack(spacing: 12) {
                        Text("f")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.facebookBlue)
                            .frame(width: 26, height: 26)
                            .background(Color.white, in: Circle())
                        Text("CONTINUE WITH FACEBOOK")
                            .font(.sb(20))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.facebookBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Continue with Facebook")

                SignInWithAppleButton(.continue, onRequest: auth.configure, onCompletion: auth.handle)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.top, 24)
            .disabled(auth.isSigningIn)
            .overlay {
                if auth.isSigningIn { ProgressView() }
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.sb(14, .semibold))
                    .foregroundStyle(.sbRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            Text("Your location is only shared with friends while you're tracking.")
                .font(.sb(13, .semibold))
                .foregroundStyle(.sbSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
        }
        .padding(.top, 32)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onDisappear { auth.errorMessage = nil }
    }
}

private extension Color {
    static let facebookBlue = Color(hex: 0x1877F2)
}
