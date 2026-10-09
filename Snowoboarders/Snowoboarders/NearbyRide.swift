//
//  NearbyRide.swift
//  Snowoboarders
//
//  Joins two phones without a server: while one shows its QR code it advertises that code over
//  Bluetooth/Wi-Fi (MultipeerConnectivity); the phone that scanned it finds the matching
//  advertiser, connects, and both swap profiles.
//

import Foundation
import MultipeerConnectivity

nonisolated final class NearbyRide: NSObject, @unchecked Sendable {
    static let serviceType = "sb-ride"
    private static let joinTimeout: TimeInterval = 15

    /// Called on the main actor when someone joins the code this phone is showing.
    var onRiderJoined: (@MainActor (Friend) -> Void)?

    private let me: Friend
    private let peer: MCPeerID
    private let session: MCSession
    private let lock = NSLock()

    // Guarded by `lock`.
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostCode: String?
    private var joinCode: String?
    private var joinContinuation: CheckedContinuation<Friend, Error>?

    init(me: Friend) {
        self.me = me
        peer = MCPeerID(displayName: String(me.displayName.prefix(40)))
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    // MARK: - Showing a code

    func startHosting(code: String) {
        lock.withLock {
            guard hostCode != code else { return }
            advertiser?.stopAdvertisingPeer()
            hostCode = code
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["code": code], serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        }
    }

    func stopHosting() {
        lock.withLock {
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
            hostCode = nil
        }
    }

    // MARK: - Joining a scanned code

    /// Finds the phone showing `code`, swaps profiles and returns the host's.
    func join(code: String) async throws -> Friend {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                joinContinuation?.resume(throwing: CancellationError())
                joinContinuation = continuation
                joinCode = code
                browser?.stopBrowsingForPeers()
                let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
                browser.delegate = self
                browser.startBrowsingForPeers()
                self.browser = browser
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.joinTimeout) { [weak self] in
                self?.finishJoin(.failure(FriendsError.notNearby), code: code)
            }
        }
    }

    private func finishJoin(_ result: Result<Friend, Error>, code: String? = nil) {
        let continuation: CheckedContinuation<Friend, Error>? = lock.withLock {
            // A timeout from an earlier attempt must not end a newer one.
            if let code, code != joinCode { return nil }
            let continuation = joinContinuation
            joinContinuation = nil
            joinCode = nil
            browser?.stopBrowsingForPeers()
            browser = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func send(profileTo peerID: MCPeerID) {
        guard let data = try? JSONEncoder().encode(me) else { return }
        try? session.send(data, toPeers: [peerID], with: .reliable)
    }
}

extension NearbyRide: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let expected = lock.withLock { hostCode }
        let offered = context.flatMap { String(data: $0, encoding: .utf8) }
        let accept = expected != nil && offered == expected
        invitationHandler(accept, accept ? session : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

extension NearbyRide: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let code = lock.withLock({ joinCode }), info?["code"] == code else { return }
        browser.invitePeer(peerID, to: session, withContext: Data(code.utf8), timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        finishJoin(.failure(error))
    }
}

extension NearbyRide: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected {
            send(profileTo: peerID)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let rider = try? JSONDecoder().decode(Friend.self, from: data), rider.id != me.id else { return }
        let isJoining = lock.withLock { joinContinuation != nil }
        if isJoining {
            finishJoin(.success(rider))
            // Give our own profile a moment to arrive before hanging up.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.session.disconnect()
            }
        } else if let onRiderJoined {
            Task { @MainActor in onRiderJoined(rider) }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
