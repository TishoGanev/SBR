//
//  RemoteFriendsService.swift
//  Snowoboarders
//
//  Talks to the Ride Together API (Server/api). The server keeps only a random id, a display name and
//  who is friends with whom; it never sees locations or rides. Without a configured host the app
//  works exactly as before, joining riders through NearbyRide only.
//

import CoreLocation
import Foundation

nonisolated struct RemoteFriendsService: FriendsService {
    private static let tokenAccount = "apiToken"
    private static let nameKey = "riderName"

    let baseURL: URL
    let identity: String

    /// Nil until `APIHost` is set in the app's Info.plist (build setting API_HOST).
    static func configured(identity: String) -> RemoteFriendsService? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "APIHost") as? String,
              !host.isEmpty, !host.hasPrefix("$(") else { return nil }
        // A bare IP address is a server on the local network; real hosts must be HTTPS.
        let scheme = host.first?.isNumber == true ? "http" : "https"
        guard let url = URL(string: "\(scheme)://\(host)/v1") else { return nil }
        return RemoteFriendsService(baseURL: url, identity: identity)
    }

    private struct Wire: Decodable {
        let id: String
        let displayName: String
        let initials: String
        let isRiding: Bool
        let lat: Double?
        let lon: Double?
        let speedKmh: Double?
        let ageSeconds: Int?

        var friend: Friend {
            Friend(id: id, displayName: displayName, initials: initials, isRiding: isRiding,
                   latitude: lat, longitude: lon, speedKmh: speedKmh,
                   updatedAt: ageSeconds.map { Date().addingTimeInterval(-TimeInterval($0)) })
        }
    }

    // MARK: - FriendsService

    func friends() async throws -> [Friend] {
        let (data, _) = try await authorized("GET", "friends")
        return try JSONDecoder().decode([Wire].self, from: data).map(\.friend)
    }

    func createInviteCode() async throws -> String {
        struct Code: Decodable { let code: String }
        let (data, _) = try await authorized("POST", "invites")
        return try JSONDecoder().decode(Code.self, from: data).code
    }

    func join(code: String) async throws -> Friend {
        do {
            let (data, _) = try await authorized("POST", "invites/\(code)/join")
            return try JSONDecoder().decode(Wire.self, from: data).friend
        } catch RemoteError.status(404) {
            throw FriendsError.invalidCode
        }
    }

    func removeFriend(id: String) async throws {
        _ = try await authorized("DELETE", "friends/\(id)")
    }

    func setRiding(_ riding: Bool, at location: CLLocation?) async throws {
        var body: [String: Any] = ["riding": riding]
        if riding, let location {
            body["lat"] = location.coordinate.latitude
            body["lon"] = location.coordinate.longitude
            // CLLocation.speed is -1 when unknown.
            body["speedKmh"] = max(0, location.speed) * 3.6
        }
        _ = try await authorized("PUT", "live", body: body)
    }

    func updateName(_ name: String) async throws {
        _ = try await authorized("PUT", "riders/me", body: ["name": name])
    }

    func registerPush(token: String, sandbox: Bool) async throws {
        _ = try await authorized("PUT", "push", body: ["platform": "ios", "token": token, "sandbox": sandbox])
    }

    // MARK: - HTTP

    private enum RemoteError: Error {
        case status(Int)
        case notRegistered
    }

    /// Sends an authenticated request, registering this install first if it has no token, and once more
    /// if the server no longer knows the token (for example after it purged an inactive rider).
    private func authorized(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (Data, Int) {
        for attempt in 0..<2 {
            let token = try await currentToken()
            do {
                return try await send(method, path, body: body, token: token)
            } catch RemoteError.status(401) where attempt == 0 {
                Keychain.delete(Self.tokenAccount)
            }
        }
        throw RemoteError.status(401)
    }

    private func currentToken() async throws -> String {
        if let token = Keychain.read(Self.tokenAccount) { return token }
        // Several calls can start at once (naming yourself and joining a code); register only once.
        return try await Registrar.shared.token { try await register() }
    }

    private func register() async throws -> String {
        guard let name = UserDefaults.standard.string(forKey: Self.nameKey) else { throw RemoteError.notRegistered }
        let (data, _) = try await send("POST", "riders", body: ["id": identity, "name": name], token: nil)
        struct Registered: Decodable { let token: String }
        let token = try JSONDecoder().decode(Registered.self, from: data).token
        Keychain.write(token, account: Self.tokenAccount)
        return token
    }

    private actor Registrar {
        static let shared = Registrar()
        private var inFlight: Task<String, Error>?

        /// One registration at a time: a caller arriving mid-registration waits for it instead of starting a second.
        func token(register: @escaping @Sendable () async throws -> String) async throws -> String {
            if let token = Keychain.read(RemoteFriendsService.tokenAccount) { return token }
            if let inFlight { return try await inFlight.value }
            let task = Task { try await register() }
            inFlight = task
            defer { inFlight = nil }
            return try await task.value
        }
    }

    private func send(_ method: String, _ path: String, body: [String: Any]?, token: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 10)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw RemoteError.status(status) }
        return (data, status)
    }
}
