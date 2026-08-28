import CryptoKit
import Foundation

public enum TransferSessionStatus: String, Codable, Sendable {
    case pending, accepted, rejected, transferring, completed, failed, cancelled
}

public protocol TransferClock: Sendable { var now: Date { get } }

public struct SystemTransferClock: TransferClock {
    public init() {}
    public var now: Date { Date() }
}

public final class MutableTransferClock: TransferClock, @unchecked Sendable {
    public var now: Date
    public init(now: Date) { self.now = now }
}

public struct TransferSessionSnapshot: Equatable, Sendable {
    public let id: String
    public let senderName: String
    public let manifest: TransferManifest
    public let manifestDigest: String
    public let verificationCode: String?
    public let status: TransferSessionStatus
    public let token: String?
    public let destination: URL?
}

public enum TransferSessionError: Error, Equatable {
    case invalidTransition
    case notFound
    case notAccepted
    case invalidToken
    case expiredToken
    case unknownFile
    case invalidProposalKey
}

public final class TransferSessionStore: @unchecked Sendable {
    private struct Session {
        var snapshot: TransferSessionSnapshot
        let proposalKey: String
        var verifiedChunks: [String: Set<Int>]
    }

    private struct TokenClaims: Codable {
        let sessionID: String
        let senderID: String
        let manifestDigest: String
        let expiresAt: TimeInterval
        let nonce: String
    }

    private let clock: any TransferClock
    private let tokenSecret: SymmetricKey
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    public init(clock: any TransferClock = SystemTransferClock(), tokenSecret: Data? = nil) {
        self.clock = clock
        self.tokenSecret = SymmetricKey(data: tokenSecret ?? Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    public func propose(manifest: TransferManifest, senderName: String, proposalKey: String, verificationCode: String? = nil) throws -> TransferSessionSnapshot {
        let digest = try ManifestCanonicalizer.sha256Hex(manifest)
        let snapshot = TransferSessionSnapshot(id: UUID().uuidString.lowercased(), senderName: senderName,
            manifest: manifest, manifestDigest: digest, verificationCode: verificationCode,
            status: .pending, token: nil, destination: nil)
        lock.withLock { sessions[snapshot.id] = Session(snapshot: snapshot, proposalKey: proposalKey, verifiedChunks: [:]) }
        return snapshot
    }

    public func accept(sessionID: String, destination: URL) throws -> TransferSessionSnapshot {
        try lock.withLock {
            guard var session = sessions[sessionID] else { throw TransferSessionError.notFound }
            guard session.snapshot.status == .pending else { throw TransferSessionError.invalidTransition }
            let token = try issueToken(for: session.snapshot)
            session.snapshot = replacing(session.snapshot, status: .accepted, token: token, destination: destination)
            sessions[sessionID] = session
            return session.snapshot
        }
    }

    public func reject(sessionID: String) throws {
        try transition(sessionID: sessionID, from: [.pending], to: .rejected)
    }

    public func cancel(sessionID: String) throws {
        try transition(sessionID: sessionID, from: [.pending, .accepted, .transferring], to: .cancelled)
    }

    public func authorizeChunk(sessionID: String, token: String, fileID: String, chunkIndex: Int) throws {
        try lock.withLock {
            guard var session = sessions[sessionID] else { throw TransferSessionError.notFound }
            guard session.snapshot.status == .accepted || session.snapshot.status == .transferring else { throw TransferSessionError.notAccepted }
            let claims = try validateToken(token)
            guard claims.sessionID == sessionID,
                  claims.senderID == session.snapshot.manifest.senderId,
                  claims.manifestDigest == session.snapshot.manifestDigest else { throw TransferSessionError.invalidToken }
            guard session.snapshot.manifest.items.contains(where: { $0.id == fileID }), chunkIndex >= 0 else { throw TransferSessionError.unknownFile }
            if session.snapshot.status == .accepted {
                session.snapshot = replacing(session.snapshot, status: .transferring)
                sessions[sessionID] = session
            }
        }
    }

    public func recordPersistedChunk(sessionID: String, fileID: String, chunkIndex: Int) throws {
        try lock.withLock {
            guard var session = sessions[sessionID] else { throw TransferSessionError.notFound }
            session.verifiedChunks[fileID, default: []].insert(chunkIndex)
            sessions[sessionID] = session
        }
    }

    public func resumeMap(sessionID: String, proposalKey: String) throws -> [String: [Int]] {
        try lock.withLock {
            guard let session = sessions[sessionID] else { throw TransferSessionError.notFound }
            guard constantTimeEqual(session.proposalKey, proposalKey) else { throw TransferSessionError.invalidProposalKey }
            return session.verifiedChunks.mapValues { $0.sorted() }
        }
    }

    public func snapshot(sessionID: String, proposalKey: String) throws -> TransferSessionSnapshot {
        try lock.withLock {
            guard let session = sessions[sessionID] else { throw TransferSessionError.notFound }
            guard constantTimeEqual(session.proposalKey, proposalKey) else { throw TransferSessionError.invalidProposalKey }
            return session.snapshot
        }
    }

    private func transition(sessionID: String, from allowed: Set<TransferSessionStatus>, to status: TransferSessionStatus) throws {
        try lock.withLock {
            guard var session = sessions[sessionID] else { throw TransferSessionError.notFound }
            guard allowed.contains(session.snapshot.status) else { throw TransferSessionError.invalidTransition }
            session.snapshot = replacing(session.snapshot, status: status)
            sessions[sessionID] = session
        }
    }

    private func issueToken(for snapshot: TransferSessionSnapshot) throws -> String {
        let claims = TokenClaims(sessionID: snapshot.id, senderID: snapshot.manifest.senderId,
            manifestDigest: snapshot.manifestDigest, expiresAt: clock.now.addingTimeInterval(300).timeIntervalSince1970,
            nonce: UUID().uuidString)
        let payload = try JSONEncoder().encode(claims)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: tokenSecret))
        return payload.base64URLEncodedString() + "." + signature.base64URLEncodedString()
    }

    private func validateToken(_ token: String) throws -> TokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let payload = Data(base64URLString: String(parts[0])),
              let supplied = Data(base64URLString: String(parts[1])) else { throw TransferSessionError.invalidToken }
        let expected = Data(HMAC<SHA256>.authenticationCode(for: payload, using: tokenSecret))
        guard constantTimeEqual(expected, supplied), let claims = try? JSONDecoder().decode(TokenClaims.self, from: payload) else {
            throw TransferSessionError.invalidToken
        }
        guard clock.now.timeIntervalSince1970 <= claims.expiresAt else { throw TransferSessionError.expiredToken }
        return claims
    }

    private func replacing(_ value: TransferSessionSnapshot, status: TransferSessionStatus,
                           token: String? = nil, destination: URL? = nil) -> TransferSessionSnapshot {
        TransferSessionSnapshot(id: value.id, senderName: value.senderName, manifest: value.manifest,
            manifestDigest: value.manifestDigest, verificationCode: value.verificationCode,
            status: status, token: token ?? value.token, destination: destination ?? value.destination)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLString: String) {
        var value = base64URLString.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}

private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}

private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    constantTimeEqual(Data(lhs.utf8), Data(rhs.utf8))
}
