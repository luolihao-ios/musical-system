import CryptoKit
import Foundation
import Network

public struct IncomingTransferRequest: Identifiable, Sendable {
    public let id: String
    public let senderName: String
    public let manifest: TransferManifest
    public let verificationCode: String
    public var fileCount: Int { manifest.items.count }
    public var totalBytes: Int64 { manifest.items.reduce(0) { $0 + $1.size } }
}

private struct ReceiverProposalRequest: Codable { let senderPublicKey: Data; let envelope: TransferEncryptedEnvelope }
private struct ReceiverProposalWire: Codable { let sessionId: String; let envelope: TransferEncryptedEnvelope }
private struct ReceiverProposalDetails: Codable { let sessionId, verificationCode, manifestDigest, proposalKey, status: String }
private struct ReceiverEncryptedStatus: Codable { let envelope: TransferEncryptedEnvelope }
private struct ReceiverStatus: Codable { let status: String; let token: String?; let verifiedChunks: [String: [Int]] }
private struct ReceiverError: Codable { let code, message: String }

public final class ReceiverServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.musetransfer.receiver")
    private let sessions: TransferSessionStore
    private let files: IncomingFileStore
    private let destination: URL
    private let privateKey = P256.KeyAgreement.PrivateKey()
    private let lock = NSLock()
    private var sessionKeys: [String: SymmetricKey] = [:]
    private var listener: NWListener?
    private var continuation: AsyncStream<IncomingTransferRequest>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public var publicKey: Data { privateKey.publicKey.x963Representation }
    public private(set) var port: UInt16?

    public init(destination: URL, temporaryRoot: URL, sessions: TransferSessionStore = TransferSessionStore()) {
        self.destination = destination; self.files = IncomingFileStore(temporaryRoot: temporaryRoot); self.sessions = sessions
    }

    public func requests() -> AsyncStream<IncomingTransferRequest> {
        AsyncStream { continuation in
            self.queue.async { self.continuation?.finish(); self.continuation = continuation }
        }
    }

    public func start(identity: TransferServiceIdentity) throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp, on: .any)
        ServiceAdvertiser.attach(identity: TransferServiceIdentity(id: identity.id, name: identity.name,
            platform: identity.platform, publicKey: publicKey), to: listener)
        listener.newConnectionHandler = { [weak self] in self?.handle($0) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.port = listener.port?.rawValue }
            if case .failed = state { self?.stop() }
        }
        self.listener = listener; listener.start(queue: queue)
    }

    public func stop() { queue.async { self.listener?.cancel(); self.listener = nil; self.port = nil } }
    public func accept(_ requestID: String) throws { _ = try sessions.accept(sessionID: requestID, destination: destination) }
    public func reject(_ requestID: String) throws { try sessions.reject(sessionID: requestID) }
    public func cancel(_ requestID: String) throws { try sessions.cancel(sessionID: requestID) }

    private func handle(_ connection: NWConnection) {
        let reader = IncomingHTTPRequestReader(connection: connection) { [weak self] result in
            guard let self else { return }
            Task {
                let response: Data
                do { response = try await self.route(result.get()) }
                catch { response = self.response(status: 400, body: (try? self.encoder.encode(ReceiverError(code: "invalid_request", message: error.localizedDescription))) ?? Data()) }
                connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        connection.stateUpdateHandler = { state in if case .ready = state { reader.receive() } }
        connection.start(queue: queue)
    }

    private func route(_ request: TransferHTTPRequest) async throws -> Data {
        let components = request.path.split(separator: "/").map(String.init)
        if request.method == "POST", request.path == "/v2/sessions" { return try propose(request) }
        guard components.count >= 3, components[0] == "v2", components[1] == "sessions" else { return error(404, "not_found", "Unknown endpoint") }
        let sessionID = components[2]
        if request.method == "GET", components.count == 3 { return try status(sessionID, request) }
        if request.method == "PUT", components.count == 7, components[3] == "files", components[5] == "chunks", let index = Int(components[6]) {
            return try await upload(sessionID: sessionID, fileID: components[4], index: index, request: request)
        }
        if request.method == "POST", components.count == 4, components[3] == "complete" { return try await complete(sessionID, request) }
        return error(404, "not_found", "Unknown endpoint")
    }

    private func propose(_ request: TransferHTTPRequest) throws -> Data {
        guard request.body.count <= 512 * 1024 else { return error(413, "proposal_too_large", "Proposal is too large") }
        let wire = try decoder.decode(ReceiverProposalRequest.self, from: request.body)
        let key = try TransferCrypto.deriveSessionKey(localPrivateKey: privateKey, remotePublicKey: wire.senderPublicKey,
            receiverPublicKey: publicKey, senderPublicKey: wire.senderPublicKey)
        let clear = try TransferCrypto.decrypt(wire.envelope, using: key, associatedData: Data("proposal|v2".utf8))
        let manifest = try decoder.decode(TransferManifest.self, from: clear)
        let digest = try ManifestCanonicalizer.sha256Hex(manifest)
        let code = TransferCrypto.verificationCode(sessionKey: key, manifestDigest: digest)
        let proposalKey = UUID().uuidString.lowercased()
        let session = try sessions.propose(manifest: manifest, senderName: manifest.senderId, proposalKey: proposalKey, verificationCode: code)
        lock.withLock { sessionKeys[session.id] = key }
        continuation?.yield(IncomingTransferRequest(id: session.id, senderName: manifest.senderId, manifest: manifest, verificationCode: code))
        let details = ReceiverProposalDetails(sessionId: session.id, verificationCode: code, manifestDigest: digest, proposalKey: proposalKey, status: "pending")
        let envelope = try TransferCrypto.encrypt(encoder.encode(details), using: key, associatedData: Data("proposal-response|\(session.id)".utf8))
        return response(status: 202, headers: ["Location": "/v2/sessions/\(session.id)"], body: try encoder.encode(ReceiverProposalWire(sessionId: session.id, envelope: envelope)))
    }

    private func status(_ sessionID: String, _ request: TransferHTTPRequest) throws -> Data {
        guard let proposalKey = request.headers["x-muse-proposal-key"] else { return error(401, "invalid_proposal_key", "Missing proposal key") }
        let snapshot = try sessions.snapshot(sessionID: sessionID, proposalKey: proposalKey)
        let chunks = try sessions.resumeMap(sessionID: sessionID, proposalKey: proposalKey)
        guard let key = lock.withLock({ sessionKeys[sessionID] }) else { return error(404, "session_not_found", "Session not found") }
        let clear = try encoder.encode(ReceiverStatus(status: snapshot.status.rawValue, token: snapshot.token, verifiedChunks: chunks))
        let envelope = try TransferCrypto.encrypt(clear, using: key, associatedData: Data("status|\(sessionID)".utf8))
        return response(status: 200, body: try encoder.encode(ReceiverEncryptedStatus(envelope: envelope)))
    }

    private func upload(sessionID: String, fileID: String, index: Int, request: TransferHTTPRequest) async throws -> Data {
        guard let token = request.headers["x-muse-session-token"], let digest = request.headers["x-muse-manifest-digest"],
              let range = parseRange(request.headers["content-range"]), let key = lock.withLock({ sessionKeys[sessionID] }) else {
            return error(401, "invalid_token", "Missing upload authorization")
        }
        try sessions.authorizeChunk(sessionID: sessionID, token: token, fileID: fileID, chunkIndex: index)
        let snapshot = try sessions.authorizeCompletion(sessionID: sessionID, token: token)
        guard digest == snapshot.manifestDigest, let item = snapshot.manifest.items.first(where: { $0.id == fileID }),
              range.total == item.size, request.body.count <= 1024 * 1024 + 28 else { return error(409, "manifest_changed", "Chunk does not match manifest") }
        let aad = Data("\(sessionID)|\(fileID)|\(index)|\(range.start)|\(range.total)|\(digest)".utf8)
        let clear = try TransferCrypto.decrypt(TransferEnvelopeCodec.unpack(request.body), using: key, associatedData: aad)
        guard Int64(clear.count) == range.end - range.start + 1 else { return error(400, "invalid_range", "Chunk length mismatch") }
        let stream = AsyncThrowingStream<Data, Error> { $0.yield(clear); $0.finish() }
        try await files.writeChunk(sessionID: sessionID, item: item, index: index, offset: range.start, bytes: stream)
        try sessions.recordPersistedChunk(sessionID: sessionID, fileID: fileID, chunkIndex: index)
        return response(status: 204)
    }

    private func complete(_ sessionID: String, _ request: TransferHTTPRequest) async throws -> Data {
        guard let token = request.headers["x-muse-session-token"] else { return error(401, "invalid_token", "Missing token") }
        let snapshot = try sessions.authorizeCompletion(sessionID: sessionID, token: token)
        guard request.headers["x-muse-manifest-digest"] == snapshot.manifestDigest else { return error(409, "manifest_changed", "Manifest digest changed") }
        for item in snapshot.manifest.items { _ = try await files.commit(sessionID: sessionID, item: item, destination: snapshot.destination ?? destination) }
        try sessions.complete(sessionID: sessionID)
        lock.withLock { sessionKeys.removeValue(forKey: sessionID) }
        return response(status: 200, body: Data("{\"status\":\"completed\"}".utf8))
    }

    private func parseRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/"); guard parts.count == 2 else { return nil }
        let bounds = parts[0].split(separator: "-"); guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]), let total = Int64(parts[1]) else { return nil }
        return (start, end, total)
    }

    private func error(_ status: Int, _ code: String, _ message: String) -> Data {
        response(status: status, body: (try? encoder.encode(ReceiverError(code: code, message: message))) ?? Data())
    }

    private func response(status: Int, headers: [String: String] = [:], body: Data = Data()) -> Data {
        let reason = [200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 413: "Content Too Large"][status] ?? "Error"
        var lines = ["HTTP/1.1 \(status) \(reason)", "Content-Length: \(body.count)", "Content-Type: application/json", "Connection: close"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }
}

private final class IncomingHTTPRequestReader: @unchecked Sendable {
    private let connection: NWConnection
    private let completion: (Result<TransferHTTPRequest, Error>) -> Void
    private var data = Data()
    init(connection: NWConnection, completion: @escaping (Result<TransferHTTPRequest, Error>) -> Void) { self.connection = connection; self.completion = completion }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] chunk, _, complete, error in
            if let chunk { data.append(chunk) }
            if data.count > 1024 * 1024 + 64 * 1024 { return completion(.failure(TransferWireError.bodyTooLarge)) }
            if let request = try? TransferHTTPRequest.parse(data, maximumHeaderBytes: 16 * 1024, maximumBodyBytes: 1024 * 1024 + 28) { return completion(.success(request)) }
            if let error { completion(.failure(error)) } else if complete { completion(.failure(TransferWireError.incompleteMessage)) } else { receive() }
        }
    }
}
