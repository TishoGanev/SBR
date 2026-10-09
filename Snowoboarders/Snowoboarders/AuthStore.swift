//
//  AuthStore.swift
//  Snowoboarders
//

import Foundation
import AuthenticationServices
import Combine
import FBSDKCoreKit
import FBSDKLoginKit

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?
    /// Any screen can ask for the sign-in sheet; ContentView presents it.
    @Published var isShowingSignIn = false

    private let service: AuthService
    private let facebookLogin = LoginManager()
    private static let userKey = "signedInUser"
    /// Apple sends the name only on the first sign-in, so it outlives sign-out.
    private static let namesKey = "appleDisplayNames"

    init(service: AuthService? = nil) {
        self.service = service ?? PlaceholderAuthService()
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(AppUser.self, from: data)
        }
    }

    var isSignedIn: Bool { user != nil }

    /// Facebook login stays disabled until the App ID is set in Secrets.xcconfig.
    static var isFacebookConfigured: Bool {
        !(Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String ?? "").isEmpty
    }

    /// The user can revoke the app in Settings › Apple ID while it isn't running.
    func verifyAppleCredential() async {
        guard let user, user.provider == .apple else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: user.id)
        if state == .revoked || state == .notFound {
            await signOut()
        }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends the name and email on the very first sign-in.
            let name = credential.fullName.flatMap {
                PersonNameComponentsFormatter().string(from: $0).trimmingCharacters(in: .whitespaces)
            }
            let request = AppleSignInRequest(
                userIdentifier: credential.user,
                identityToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) },
                authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                displayName: name?.isEmpty == false ? name : nil,
                email: credential.email
            )
            Task { await signIn(request) }
        }
    }

    func signInWithFacebook() {
        guard Self.isFacebookConfigured else {
            errorMessage = "Facebook login isn't set up yet. Add FACEBOOK_APP_ID and FACEBOOK_CLIENT_TOKEN to Secrets.xcconfig."
            return
        }
        // Limited Login needs no tracking prompt and returns a signed token the server can verify.
        let nonce = UUID().uuidString
        guard let configuration = LoginConfiguration(
            permissions: ["public_profile", "email", "user_friends"],
            tracking: .limited,
            nonce: nonce
        ) else { return }

        facebookLogin.logIn(configuration: configuration) { [weak self] result in
            Task { @MainActor in self?.handleFacebook(result, nonce: nonce) }
        }
    }

    private func handleFacebook(_ result: LoginResult, nonce: String) {
        switch result {
        case .cancelled:
            return
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .success:
            guard let profile = Profile.current else {
                errorMessage = "Facebook didn't return a profile."
                return
            }
            let request = FacebookSignInRequest(
                userID: profile.userID,
                authenticationToken: AuthenticationToken.current?.tokenString,
                nonce: nonce,
                displayName: profile.name,
                email: profile.email,
                friendIDs: profile.friendIDs ?? []
            )
            Task {
                await perform { try await self.service.signInWithFacebook(request) }
            }
        }
    }

    private func perform(_ signIn: () async throws -> AppUser) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            save(try await signIn())
            errorMessage = nil
            isShowingSignIn = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signIn(_ request: AppleSignInRequest) async {
        var names = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
        let request = AppleSignInRequest(
            userIdentifier: request.userIdentifier,
            identityToken: request.identityToken,
            authorizationCode: request.authorizationCode,
            displayName: request.displayName ?? names[request.userIdentifier],
            email: request.email
        )
        await perform { try await self.service.signInWithApple(request) }
        if let user {
            names[user.id] = user.displayName
            UserDefaults.standard.set(names, forKey: Self.namesKey)
        }
    }

    func signOut() async {
        if user?.provider == .facebook {
            facebookLogin.logOut()
        }
        await service.signOut()
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    private func save(_ user: AppUser) {
        self.user = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }
}

@MainActor
final class FriendsStore: ObservableObject {
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var invite: Invite?
    @Published private(set) var isJoining = false
    @Published var joinError: String?
    /// The rider who just joined, shown as a confirmation in the Ride Together sheet.
    @Published var justJoined: Friend?
    /// Any screen can ask for the Ride Together sheet; ContentView presents it.
    @Published var isShowingRideTogether = false
    /// A scanned link that arrived while signed out; joined right after sign-in.
    @Published var pendingInvite: String?

    private let service: FriendsService
    private var me: Friend?
    private var nearby: NearbyRide?

    init(service: FriendsService? = nil) {
        self.service = service ?? PlaceholderFriendsService()
    }

    var ridingNow: [Friend] { friends.filter(\.isRiding) }

    /// Called when the signed-in user changes; nearby joining needs to know who "me" is.
    func setRider(_ user: AppUser?) {
        nearby?.stopHosting()
        nearby = nil
        invite = nil
        justJoined = nil
        me = user.map(Friend.init)
        guard let me else {
            friends = []
            return
        }
        let nearby = NearbyRide(me: me)
        nearby.onRiderJoined = { [weak self] rider in self?.save(rider) }
        self.nearby = nearby
    }

    func refresh() async {
        friends = (try? await service.friends()) ?? friends
    }

    func loadInvite() async {
        guard invite == nil, let me, let code = try? await service.createInviteCode() else { return }
        invite = Invite(code: code, inviter: me)
    }

    /// While the QR code is on screen, nearby phones that scanned it can connect to this one.
    func startHosting() {
        guard let invite else { return }
        nearby?.startHosting(code: invite.code)
    }

    func stopHosting() {
        nearby?.stopHosting()
    }

    /// Joins from a scanned QR payload, an opened invite link or a typed code.
    func join(_ text: String) async {
        guard !isJoining else { return }
        guard let (code, inviter) = InviteLink.parse(text) else {
            joinError = FriendsError.invalidCode.localizedDescription
            return
        }
        guard let me, let nearby else {
            joinError = FriendsError.signedOut.localizedDescription
            return
        }
        let ownCode = try? await service.createInviteCode()
        if code == ownCode || inviter?.id == me.id {
            joinError = FriendsError.ownInvite.localizedDescription
            return
        }

        isJoining = true
        defer { isJoining = false }
        do {
            save(try await nearby.join(code: code))
        } catch {
            // The QR already says who invited us, so we can still ride with them;
            // only their phone won't know until they scan ours back.
            if let inviter {
                save(inviter)
            } else {
                joinError = error.localizedDescription
            }
        }
    }

    private func save(_ rider: Friend) {
        TodayCrew.add(rider)
        friends = TodayCrew.load()
        justJoined = rider
        joinError = nil
    }
}
