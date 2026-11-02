//
//  FriendsStore.swift
//  Snowoboarders
//

import CoreLocation
import Foundation
import SwiftUI
import Combine

@MainActor
final class FriendsStore: ObservableObject {
    /// You, as nearby riders see you. Nil until the rider has entered a name.
    @Published private(set) var me: Friend?
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var invite: Invite?
    @Published private(set) var isJoining = false
    @Published var joinError: String?
    /// The rider who just joined, shown as a confirmation in the Ride Together sheet.
    @Published var justJoined: Friend?
    /// Any screen can ask for the Ride Together sheet; ContentView presents it.
    @Published var isShowingRideTogether = false
    /// A scanned link that arrived before the rider entered a name; joined right after.
    @Published var pendingInvite: String?
    /// True from the moment this rider shows an invite until the app closes or they leave: they are waiting for
    /// people to join, so their position is already on the server when the first one does.
    @Published private(set) var isInviting = false

    /// The Ride Together server; nil when no API host is configured, and the app then runs on nearby joins alone.
    private let remote: FriendsService?
    private let local = PlaceholderFriendsService()
    private var nearby: NearbyRide?
    private var ridingLoop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var quickRefresh: Task<Void, Never>?
    /// The push token the server already has, so it is sent once per change rather than on every refresh.
    private var sentPushToken: String?
    private static let nameKey = "riderName"
    private static let pendingJoinsKey = "pendingServerJoins"

    /// Stable per install, so a rider you met today isn't added twice if they reopen the sheet.
    private static var deviceIdentity: String {
        if let saved = UserDefaults.standard.string(forKey: "voiceIdentity") { return saved }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "voiceIdentity")
        return id
    }

    init(service: FriendsService? = nil) {
        self.remote = service ?? RemoteFriendsService.configured(identity: Self.deviceIdentity)
        if let name = UserDefaults.standard.string(forKey: Self.nameKey) {
            startAs(name: name)
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .pushTokenChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.syncPushToken() }
            },
            // A friend joined or left: show it right away rather than at the next refresh.
            center.addObserver(forName: .crewPushReceived, object: nil, queue: .main) { [weak self] note in
                let joined = note.userInfo?["event"] as? String == "join"
                Task { @MainActor in
                    // Someone joined while our invite was on screen: close it, the notification says who.
                    if joined { self?.isShowingRideTogether = false }
                    await self?.refresh()
                    self?.refreshQuickly()
                }
            },
            center.addObserver(forName: .crewPushOpened, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.refresh()
                    self?.refreshQuickly()
                }
            },
        ]
        // Already allowed earlier: pick up the (possibly new) device token.
        if me != nil { Task { await Push.enable() } }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Tells the server where to reach this phone. Needs the rider to have a name, as registering does.
    private func syncPushToken() async {
        guard me != nil, let remote, let token = Push.token, token != sentPushToken else { return }
        do {
            try await remote.registerPush(token: token, sandbox: Push.isSandbox)
            sentPushToken = token
        } catch {
            // No signal: tried again with the next refresh.
        }
    }

    var ridingNow: [Friend] { friends.filter(\.isRiding) }

    /// Saves the rider's name and starts presenting them to nearby phones under it. There are no accounts:
    /// the name lives on this phone and is shared only with riders who join your code.
    func setName(_ raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !name.isEmpty else { return }
        UserDefaults.standard.set(name, forKey: Self.nameKey)
        startAs(name: name)
        Task { try? await remote?.updateName(name) }
        if let pending = pendingInvite {
            pendingInvite = nil
            Task { await join(pending) }
        }
    }

    private func startAs(name: String) {
        nearby?.stopHosting()
        invite = nil
        justJoined = nil
        let me = Friend(id: Self.deviceIdentity, displayName: name, initials: Self.initials(from: name))
        self.me = me
        let nearby = NearbyRide(me: me)
        // Someone scanned our code: they are in the crew now, with nothing for us to confirm.
        nearby.onRiderJoined = { [weak self] rider in
            self?.save(rider, confirming: false)
            self?.isShowingRideTogether = false
            self?.refreshQuickly()
        }
        self.nearby = nearby
    }

    nonisolated static func initials(from name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }

    /// Server friends first (they carry the live riding state), then anyone met today who isn't on the server yet.
    func refresh() async {
        await syncPendingJoins()
        await syncPushToken()
        guard let known = try? await remote?.friends() else {
            // No signal (or no server): keep who we have rather than showing an empty crew.
            friends = Self.merged(friends, TodayCrew.load())
            return
        }
        // The server is the truth while reachable: a friend who left the crew is gone from its list,
        // so drop them here too unless their join is still on its way to the server.
        TodayCrew.prune(serverIDs: Set(known.map(\.id)), keeping: Set(pendingJoins.values))
        // Anyone the server doesn't list yet can't be confirmed as riding.
        let unconfirmed = TodayCrew.load().map {
            Friend(id: $0.id, displayName: $0.displayName, initials: $0.initials, isRiding: false)
        }
        // Riders glide to their new position rather than jumping.
        withAnimation(.easeOut(duration: 0.45)) {
            friends = Self.merged(known, unconfirmed)
        }
    }

    /// Right after someone joins, look again every couple of seconds for a short while, so the new rider shows up on
    /// the map as soon as their phone sends its first position rather than at the next slow poll.
    func refreshQuickly() {
        quickRefresh?.cancel()
        quickRefresh = Task { [weak self] in
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    private static func merged(_ lists: [Friend]...) -> [Friend] {
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    func loadInvite() async {
        guard invite == nil, let me else { return }
        // The server's code lets friends join from anywhere; offline we still hand out a local one for nearby joins.
        var code = try? await remote?.createInviteCode()
        if code == nil { code = try? await local.createInviteCode() }
        guard let code else { return }
        invite = Invite(code: code, inviter: me)
        // The moment a rider sets up a crew is when "your friend joined" is worth allowing.
        await Push.enable()
    }

    /// While the QR code is on screen, nearby phones that scanned it can connect to this one.
    func startHosting() {
        guard let invite else { return }
        isInviting = true
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
            joinError = FriendsError.noName.localizedDescription
            return
        }
        var ownCode = invite?.code
        if ownCode == nil { ownCode = try? await local.createInviteCode() }
        if code == ownCode || inviter?.id == me.id {
            joinError = FriendsError.ownInvite.localizedDescription
            return
        }

        isJoining = true
        defer { isJoining = false }
        do {
            let rider = try await nearby.join(code: code)
            save(rider)
            await joinOnServer(code, riderID: rider.id)
        } catch {
            // Out of Bluetooth range: the server can still connect us if there is signal.
            if let friend = try? await remote?.join(code: code) {
                save(friend)
            } else if let inviter {
                // The QR already says who invited us, so we can still ride with them; the server
                // learns about it when there is signal again.
                save(inviter)
                queueServerJoin(code, riderID: inviter.id)
            } else {
                joinError = error.localizedDescription
            }
        }
        // Joining a code brings the owner's whole crew with it; pick them up now.
        if joinError == nil {
            await refresh()
            refreshQuickly()
        }
    }

    /// Records the friendship on the server after a nearby handshake, or queues it for later.
    private func joinOnServer(_ code: String, riderID: String) async {
        guard let remote else { return }
        do {
            _ = try await remote.join(code: code)
        } catch {
            queueServerJoin(code, riderID: riderID)
        }
    }

    /// Joins still waiting for signal: invite code -> id of the rider it belongs to.
    private var pendingJoins: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.pendingJoinsKey) as? [String: String] ?? [:]
    }

    private func queueServerJoin(_ code: String, riderID: String) {
        guard remote != nil else { return }
        UserDefaults.standard.set(pendingJoins.merging([code: riderID]) { _, new in new }, forKey: Self.pendingJoinsKey)
    }

    private func syncPendingJoins() async {
        guard let remote, me != nil else { return }
        var left: [String: String] = [:]
        for (code, riderID) in pendingJoins {
            do {
                _ = try await remote.join(code: code)
            } catch {
                // An unknown code will never work; anything else (no signal) is worth another try.
                if (error as? FriendsError) != .invalidCode { left[code] = riderID }
            }
        }
        UserDefaults.standard.set(left, forKey: Self.pendingJoinsKey)
    }

    /// Whether this rider's position is being shared with their crew right now.
    private(set) var isSharing = false

    /// Shares this rider's position with their friends, and keeps theirs fresh, while `sharing` is true: that is
    /// whenever a ride is being recorded or the rider is in a crew. Only friends see it, only the latest position
    /// is kept, and it expires on the server a minute after the app stops sending.
    func setSharing(_ sharing: Bool, location: @escaping @MainActor () -> CLLocation?) {
        guard sharing != isSharing || (sharing && ridingLoop == nil) else { return }
        ridingLoop?.cancel()
        ridingLoop = nil
        isSharing = sharing
        guard let remote, me != nil else { isSharing = false; return }
        guard sharing else {
            Task { try? await remote.setRiding(false, at: nil) }
            return
        }
        ridingLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await remote.setRiding(true, at: location())
                await self?.refresh()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    /// Leaves the crew: removes everyone from your friends on this phone and the server. Each of them is told you left.
    func leave() {
        let ids = friends.map(\.id)
        UserDefaults.standard.removeObject(forKey: Self.pendingJoinsKey)
        Task {
            for id in ids { try? await remote?.removeFriend(id: id) }
        }
        TodayCrew.clear()
        friends = []
        justJoined = nil
        isInviting = false
    }

    private func save(_ rider: Friend, confirming: Bool = true) {
        TodayCrew.add(rider)
        friends = Self.merged(TodayCrew.load(), friends)
        justJoined = confirming ? rider : nil
        joinError = nil
        Task { await Push.enable() }
    }
}
