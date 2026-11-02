//
//  Backend.swift
//  Snowoboarders
//
//  Ride Together types. There are no accounts and no server yet: the invite code is generated on this
//  phone and friends come from nearby handshakes (see NearbyRide).
//

import CoreLocation
import Foundation

nonisolated struct Friend: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    let initials: String
    let isRiding: Bool
    /// Where they were last, and how fast they went; only set while a recent position is known.
    let latitude: Double?
    let longitude: Double?
    let speedKmh: Double?
    /// When that position was sent.
    let updatedAt: Date?

    /// Stable per rider, and the same everywhere the rider shows up (map tag, crew bar, avatars).
    /// The brand red is left out on purpose: it belongs to the app and to your own track.
    private static let riderColors: [UInt32] = [0x3D7FD9, 0x3A9E57, 0x8C6AD6, 0xC17F1E, 0xD2556B]

    var avatarColor: UInt32 {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.riderColors[hash % Self.riderColors.count]
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A rider as others see them.
    init(id: String, displayName: String, initials: String, isRiding: Bool = true,
         latitude: Double? = nil, longitude: Double? = nil, speedKmh: Double? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
        self.isRiding = isRiding
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.updatedAt = updatedAt
    }
}

/// An invite to ride together. The QR code encodes `url`; scanning it opens the app and joins.
struct Invite: Equatable {
    let code: String
    /// Carried in the QR so the scanner knows who invited them even before the phones connect.
    let inviter: Friend?

    var url: URL { InviteLink.url(for: code, inviter: inviter) }
}

enum InviteLink {
    /// Legacy link, still accepted from older QR codes and used when no web host is configured.
    static let scheme = "snowboarder"

    /// The API's host (for example "ridersapi.sportco.net"), which serves https://<host>/join/<code> so the link is
    /// tappable in Viber, WhatsApp and the like. Nil when the app talks to a bare IP address.
    static var webHost: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "APIHost") as? String, !value.hasPrefix("$(") else { return nil }
        let host = String(value.split(separator: "/").first ?? "")
        return host.isEmpty || host.first?.isNumber == true ? nil : host
    }

    static func url(for code: String, inviter: Friend?) -> URL {
        var components = URLComponents()
        if let host = webHost {
            components.scheme = "https"
            components.host = host
            components.path = "/join/\(code)"
            return components.url!
        }
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

    /// Whether `url` is an invite for this app: https://<web host>/join/<code> or the legacy snowboarder:// form.
    static func isInvite(_ url: URL) -> Bool {
        if url.scheme == scheme { return url.host == "join" }
        return url.scheme == "https" && url.host == webHost && url.path.hasPrefix("/join/")
    }

    /// Accepts a scanned or opened invite URL, or a typed code such as "ABCD-2345".
    static func parse(_ text: String) -> (code: String, inviter: Friend?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let url = components.url, isInvite(url) else {
            return normalize(trimmed).map { ($0, nil) }
        }
        guard let code = normalize(components.scheme == scheme ? components.path : String(components.path.dropFirst("/join/".count))) else { return nil }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        var inviter: Friend?
        if let id = items["id"], !id.isEmpty, let name = items["name"], !name.isEmpty {
            inviter = Friend(id: id, displayName: name, initials: items["initials"] ?? FriendsStore.initials(from: name))
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
        /// When each rider was added (seconds since 1970), so a rider the server hasn't heard of yet gets time to sync.
        var added: [String: Double]?
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

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func add(_ rider: Friend) {
        var stored = current()
        stored.riders.removeAll { $0.id == rider.id }
        stored.riders.append(rider)
        stored.added = (stored.added ?? [:]).merging([rider.id: Date().timeIntervalSince1970]) { _, new in new }
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    /// Forgets riders the server no longer lists (they left the crew), unless they were added within `grace`
    /// seconds or `keeping` says their join hasn't reached the server yet.
    static func prune(serverIDs: Set<String>, keeping: Set<String>, grace: TimeInterval = 600) {
        var stored = current()
        let now = Date().timeIntervalSince1970
        stored.riders.removeAll { rider in
            !serverIDs.contains(rider.id) && !keeping.contains(rider.id)
                && now - (stored.added?[rider.id] ?? 0) > grace
        }
        stored.added = stored.added?.filter { id, _ in stored.riders.contains { $0.id == id } }
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    private static func current() -> Stored {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.day == today else { return Stored(day: today, riders: [], added: [:]) }
        return stored
    }
}

nonisolated enum FriendsError: LocalizedError, Equatable {
    case ownInvite, invalidCode, notNearby, noName

    var errorDescription: String? {
        switch self {
        case .ownInvite: "That's your own code. Let a friend scan it instead."
        case .invalidCode: "That code doesn't look right. Codes are 8 letters and numbers."
        case .notNearby: "Couldn't reach your friend's phone. Keep their code on screen, stay close and try again."
        case .noName: "Add your name first to ride together."
        }
    }
}

protocol FriendsService {
    /// Friends and whether they are riding right now (`GET /v1/friends`).
    func friends() async throws -> [Friend]
    /// Your invite code (`POST /v1/invites`).
    func createInviteCode() async throws -> String
    /// Becomes friends with whoever owns `code` (`POST /v1/invites/{code}/join`).
    func join(code: String) async throws -> Friend
    func removeFriend(id: String) async throws
    /// Heartbeat while a ride is being recorded, with the rider's position so friends can see them on the map.
    /// The server expires it after 90 seconds and keeps only the latest position (`PUT /v1/live`).
    func setRiding(_ riding: Bool, at location: CLLocation?) async throws
    func updateName(_ name: String) async throws
    /// Where the server should send "joined / left your crew" (`PUT /v1/push`).
    func registerPush(token: String, sandbox: Bool) async throws
}

/// Used when no server is configured or reachable: friends are today's crew from nearby handshakes
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

    func join(code: String) async throws -> Friend { throw FriendsError.notNearby }
    func removeFriend(id: String) async throws {}
    func setRiding(_ riding: Bool, at location: CLLocation?) async throws {}
    func updateName(_ name: String) async throws {}
    func registerPush(token: String, sandbox: Bool) async throws {}
}
