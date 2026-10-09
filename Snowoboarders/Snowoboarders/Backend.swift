//
//  Backend.swift
//  Snowoboarders
//
//  The app's only contact point with the friends server. Everything here is a local placeholder
//  until the PHP API exists; swap the placeholder types for real URLSession implementations then.
//

import Foundation

nonisolated enum AuthProvider: String, Codable {
    case apple, facebook
}

nonisolated struct AppUser: Codable, Equatable {
    let id: String
    var displayName: String
    var initials: String
    var provider: AuthProvider?
}

nonisolated struct Friend: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    let initials: String
    let avatarColor: UInt32
    let isRiding: Bool

    private static let avatarColors: [UInt32] = [0x353535, 0x8A8A8A, 0xED213D]

    /// A rider as others see them; the avatar colour is stable for the same id.
    init(id: String, displayName: String, initials: String, isRiding: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.isRiding = isRiding
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        avatarColor = Self.avatarColors[hash % Self.avatarColors.count]
    }

    init(_ user: AppUser) {
        self.init(id: user.id, displayName: user.displayName, initials: user.initials)
    }
}

/// What the client sends the server after Sign in with Apple succeeds.
struct AppleSignInRequest {
    let userIdentifier: String
    let identityToken: String?
    let authorizationCode: String?
    let displayName: String?
    let email: String?
}

/// What the client sends the server after Facebook Limited Login succeeds. The server verifies
/// `authenticationToken` (an OpenID Connect JWT) against Facebook's keys and checks `nonce`.
struct FacebookSignInRequest {
    let userID: String
    let authenticationToken: String?
    let nonce: String
    let displayName: String?
    let email: String?
    /// Facebook friends who also use the app (`user_friends` permission).
    let friendIDs: [String]
}

protocol AuthService {
    /// Exchanges a Facebook credential for a server session (`POST /v1/auth/facebook`).
    func signInWithFacebook(_ request: FacebookSignInRequest) async throws -> AppUser
    /// Exchanges an Apple credential for a server session (`POST /v1/auth/apple`).
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppUser
    /// Ends the server session.
    func signOut() async
}

/// An invite to ride together. The QR code encodes `url`; scanning it opens the app and joins.
struct Invite: Equatable {
    let code: String
    /// Carried in the QR so the scanner knows who invited them even before the phones connect.
    let inviter: Friend?

    var url: URL { InviteLink.url(for: code, inviter: inviter) }
}

enum InviteLink {
    /// Custom scheme for now; switch to a universal link (https://<domain>/i/<code>) once the server serves one.
    static let scheme = "snowboarder"

    static func url(for code: String, inviter: Friend?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "join"
        components.path = "/\(code)"
        if let inviter {
            components.queryItems = [
                URLQueryItem(name: "id", value: inviter.id),
                URLQueryItem(name: "name", value: inviter.displayName),
                URLQueryItem(name: "initials", value: inviter.initials),
            ]
        }
        return components.url!
    }

    /// Accepts a scanned or opened invite URL, or a typed code such as "ABCD-2345".
    static func parse(_ text: String) -> (code: String, inviter: Friend?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == scheme, components.host == "join" else {
            return normalize(trimmed).map { ($0, nil) }
        }
        guard let code = normalize(components.path) else { return nil }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        var inviter: Friend?
        if let id = items["id"], !id.isEmpty, let name = items["name"], !name.isEmpty {
            inviter = Friend(id: id, displayName: name, initials: items["initials"] ?? PlaceholderAuthService.initials(from: name))
        }
        return (code, inviter)
    }

    private static func normalize(_ raw: String) -> String? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return code.count == 8 ? code : nil
    }
}

/// Riders you joined today, kept on this phone only. Everything resets at midnight.
enum TodayCrew {
    private static let key = "todayCrew"

    private struct Stored: Codable {
        let day: String
        var riders: [Friend]
    }

    private static var today: String {
        Date().formatted(.iso8601.year().month().day())
    }

    static func load() -> [Friend] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.day == today else { return [] }
        return stored.riders
    }

    static func add(_ rider: Friend) {
        var riders = load()
        riders.removeAll { $0.id == rider.id }
        riders.append(rider)
        UserDefaults.standard.set(try? JSONEncoder().encode(Stored(day: today, riders: riders)), forKey: key)
    }
}

nonisolated enum FriendsError: LocalizedError {
    case ownInvite, invalidCode, notNearby, signedOut

    var errorDescription: String? {
        switch self {
        case .ownInvite: "That's your own code. Let a friend scan it instead."
        case .invalidCode: "That code doesn't look right. Codes are 8 letters and numbers."
        case .notNearby: "Couldn't reach your friend's phone. Keep their code on screen, stay close and try again."
        case .signedOut: "Sign in first to ride together."
        }
    }
}

protocol FriendsService {
    /// Friends and whether they are riding right now (`GET /v1/friends` + `GET /v1/live/friends`).
    func friends() async throws -> [Friend]
    /// Your current invite code (`POST /v1/invites`).
    func createInviteCode() async throws -> String
}

/// Placeholder until the server exists: trusts Apple's credential locally and makes a profile from it.
struct PlaceholderAuthService: AuthService {
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppUser {
        let name = request.displayName
            ?? request.email.map { String($0.split(separator: "@").first ?? "") }
            ?? "Rider"
        return AppUser(id: request.userIdentifier, displayName: name, initials: Self.initials(from: name), provider: .apple)
    }

    func signInWithFacebook(_ request: FacebookSignInRequest) async throws -> AppUser {
        let name = request.displayName ?? "Rider"
        return AppUser(id: request.userID, displayName: name, initials: Self.initials(from: name), provider: .facebook)
    }

    func signOut() async {}

    static func initials(from name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }
}

/// Placeholder until the server exists: friends are today's crew from nearby handshakes
/// (see NearbyRide), and the invite code is generated on this phone.
struct PlaceholderFriendsService: FriendsService {
    private static let inviteKey = "placeholderInviteCode"
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    func friends() async throws -> [Friend] {
        TodayCrew.load()
    }

    func createInviteCode() async throws -> String {
        if let code = UserDefaults.standard.string(forKey: Self.inviteKey) {
            return code
        }
        let code = String((0..<8).map { _ in Self.alphabet.randomElement()! })
        UserDefaults.standard.set(code, forKey: Self.inviteKey)
        return code
    }
}
