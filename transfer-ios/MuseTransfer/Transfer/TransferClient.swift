import CryptoKit
import Foundation

public struct OutgoingFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let relativePath: String
    public init(id: String = UUID().uuidString.lowercased(), url: URL, relativePath: String? = nil) {
        self.id = id; self.url = url; self.relativePath = relativePath ?? url.lastPathComponent
    }
}

public struct TransferProgress: Equatable, Sendable {
    public let transferredBytes: Int64
    public let totalBytes: Int64
    public let currentFile: String
}

private struct EncryptedProposalRequest: Codable { let senderPublicKey: Data; let envelope: TransferEncryptedEnvelope }
private struct ProposalWireResponse: Codable { let sessionId: String; let envelope: TransferEncryptedEnvelope }
private struct ProposalDetails: Codable { let sessionId, verificationCode, manifestDigest, proposalKey, status: String }
private struct EncryptedStatusResponse: Codable { let envelope: TransferEncryptedEnvelope }
private struct SessionStatusResponse: Codable { let status: String; let token: String?; let verifiedChunks: [String: [Int]] }

public final class TransferClient: @unchecked Sendable {
    private let transport: NWHTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(transport: NWHTTPTransport = NWHTTPTransport()) { self.transport = transport }

    public func send(files: [OutgoingFile], to device: NearbyDevice,
                     progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try await send(files: files, address: device.address, receiverPublicKey: device.receiverPublicKey, senderID: ProcessInfo.processInfo.hostName, progress: progress)
    }

    public func send(files: [OutgoingFile], manualEndpoint: TransferEndpoint, receiverPublicKey: Data,
                     progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try await send(files: files, address: .manual(manualEndpoint), receiverPublicKey: receiverPublicKey,
                       senderID: ProcessInfo.processInfo.hostName, progress: progress)
    }

    private func send(files: [OutgoingFile], address: NearbyAddress, receiverPublicKey: Data, senderID: String,
                      progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        guard !files.isEmpty, receiverPublicKey.count == 65 else { throw TransferWireError.invalidEndpoint }
        let sender = P256.KeyAgreement.PrivateKey()
        let senderPublic = sender.publicKey.x963Representation
        let key = try TransferCrypto.deriveSessionKey(localPrivateKey: sender, remotePublicKey: receiverPublicKey,
            receiverPublicKey: receiverPublicKey, senderPublicKey: senderPublic)
        let manifest = try buildManifest(files: files, senderID: senderID)
        let manifestData = try encoder.encode(manifest)
        let encrypted = try TransferCrypto.encrypt(manifestData, using: key, associatedData: Data("proposal|v2".utf8))
        let proposalBody = try encoder.encode(EncryptedProposalRequest(senderPublicKey: senderPublic, envelope: encrypted))
        let proposalResponse = try await request("POST", "/v2/sessions", body: proposalBody, address: address, expected: 202,
                                                 contentType: "application/json")
        let wire = try decoder.decode(ProposalWireResponse.self, from: proposalResponse.body)
        let detailData = try TransferCrypto.decrypt(wire.envelope, using: key,
            associatedData: Data("proposal-response|\(wire.sessionId)".utf8))
        let proposal = try decoder.decode(ProposalDetails.self, from: detailData)
        let decision = try await waitForAcceptance(proposal: proposal, key: key, address: address)
        guard let token = decision.token else { throw TransferTransportError.invalidResponse }

        let total = manifest.items.reduce(Int64(0)) { $0 + $1.size }
        var transferred: Int64 = 0
        for (file, item) in zip(files, manifest.items) {
            let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
            var index = 0
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                let offset = try handle.offset() - UInt64(chunk.count)
                if decision.verifiedChunks[item.id]?.contains(index) == true {
                    transferred += Int64(chunk.count); index += 1; continue
                }
                let aad = Data("\(proposal.sessionId)|\(item.id)|\(index)|\(offset)|\(item.size)|\(proposal.manifestDigest)".utf8)
                let packed = try TransferEnvelopeCodec.pack(TransferCrypto.encrypt(chunk, using: key, associatedData: aad))
                _ = try await request("PUT", "/v2/sessions/\(proposal.sessionId)/files/\(item.id)/chunks/\(index)",
                    headers: ["X-Muse-Session-Token": token, "X-Muse-Manifest-Digest": proposal.manifestDigest,
                              "Content-Range": "bytes \(offset)-\(offset + UInt64(chunk.count) - 1)/\(item.size)"],
                    body: packed, address: address, expected: 204, contentType: "application/octet-stream")
                transferred += Int64(chunk.count); index += 1
                progress(TransferProgress(transferredBytes: transferred, totalBytes: total, currentFile: item.relativePath))
            }
        }
        _ = try await request("POST", "/v2/sessions/\(proposal.sessionId)/complete",
            headers: ["X-Muse-Session-Token": token, "X-Muse-Manifest-Digest": proposal.manifestDigest],
            address: address, expected: 200)
    }

    private func waitForAcceptance(proposal: ProposalDetails, key: SymmetricKey, address: NearbyAddress) async throws -> SessionStatusResponse {
        while true {
            try Task.checkCancellation()
            let response = try await request("GET", "/v2/sessions/\(proposal.sessionId)",
                headers: ["X-Muse-Proposal-Key": proposal.proposalKey], address: address, expected: 200)
            let wire = try decoder.decode(EncryptedStatusResponse.self, from: response.body)
            let clear = try TransferCrypto.decrypt(wire.envelope, using: key, associatedData: Data("status|\(proposal.sessionId)".utf8))
            let state = try decoder.decode(SessionStatusResponse.self, from: clear)
            if state.status == "accepted" || state.status == "transferring" { return state }
            if ["rejected", "cancelled", "failed"].contains(state.status) { throw TransferTransportError.rejected(response.statusCode, state.status) }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func request(_ method: String, _ path: String, headers: [String: String] = [:], body: Data = Data(),
                         address: NearbyAddress, expected: Int, contentType: String? = nil) async throws -> TransferHTTPResponse {
        var all = headers; if let contentType { all["Content-Type"] = contentType }
        let response = try await transport.send(method: method, path: path, headers: all, body: body, to: address)
        guard response.statusCode == expected else { throw TransferTransportError.rejected(response.statusCode, String(data: response.body, encoding: .utf8) ?? "") }
        return response
    }

    private func buildManifest(files: [OutgoingFile], senderID: String) throws -> TransferManifest {
        let items = try files.map { file -> TransferItem in
            let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
            var hasher = SHA256(); var size: Int64 = 0
            while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hasher.update(data: data); size += Int64(data.count) }
            return TransferItem(id: file.id, relativePath: file.relativePath, size: size,
                sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
        }
        return TransferManifest(protocolVersion: 2, senderId: senderID, items: items, musicGroups: MusicGrouper.group(items))
    }
}
