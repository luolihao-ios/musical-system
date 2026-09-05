import Foundation
import Network

public struct IncomingTransfer: Identifiable, Sendable {
    public let id: String
    public let sender: DeviceInfo
    public let files: [String: FileMetadata]
}

public final class LocalSendReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.aiyuetransfer.receiver")
    private let destination: URL
    private let local: DeviceInfo
    private var listener: NWListener?
    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var tokens: [String: [String: String]] = [:]
    private var fileNames: [String: [String: String]] = [:]
    public var onIncomingTransfer: (@Sendable (IncomingTransfer) -> Void)?

    public init(local: DeviceInfo, destination: URL) { self.local = local; self.destination = destination }

    public func start() throws {
        guard listener == nil else { return }
        DiagnosticLog.write("iOS receiver starting on TCP \(local.port).")
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(local.port))!)
        // A listener alone is not discoverable. Publishing this Bonjour service is
        // the iOS half of the Windows mDNS advertisement.
        let txtRecord = NetService.data(fromTXTRecord: [
            "alias": Data(local.alias.utf8),
            "deviceType": Data(local.deviceType.utf8),
            "fingerprint": Data(local.fingerprint.utf8),
            "protocol": Data("http".utf8)
        ])
        listener.service = NWListener.Service(name: "aiyue-\(local.fingerprint.prefix(12))", type: "_aiyue._tcp", domain: nil, txtRecord: txtRecord)
        listener.stateUpdateHandler = { state in DiagnosticLog.write("iOS receiver state: \(String(describing: state)).") }
        listener.newConnectionHandler = { [weak self] connection in
            DiagnosticLog.write("iOS receiver accepted a TCP connection.")
            self?.receive(connection)
        }
        self.listener = listener; listener.start(queue: queue)
    }

    public func stop() { queue.async { DiagnosticLog.write("iOS receiver stopped."); self.listener?.cancel(); self.listener = nil } }
    public func decide(sessionID: String, accepted: Bool) { queue.async { self.pending.removeValue(forKey: sessionID)?.resume(returning: accepted) } }

    private func receive(_ connection: NWConnection) {
        var buffer = Data()
        func read() { connection.receive(minimumIncompleteLength: 1, maximumLength: 2 * 1024 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }; if let data { buffer.append(data) }
            if let error { DiagnosticLog.write("iOS receiver connection failed: \(error.localizedDescription)."); connection.cancel(); return }
            guard let request = Self.parse(buffer) else { if !complete { read() }; return }
            Task { let response = await self.route(request); connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }) }
        } }
        connection.start(queue: queue); read()
    }

    private func route(_ request: HTTPRequest) async -> Data {
        if request.method == "POST", request.path == "/api/aiyue/v1/register" { return Self.response(200, try? JSONEncoder().encode(local)) }
        if request.method == "POST", request.path == "/api/aiyue/v1/prepare-upload" {
            let value: PrepareUploadRequest
            do {
                value = try JSONDecoder().decode(PrepareUploadRequest.self, from: request.body)
            } catch {
                DiagnosticLog.write("Prepare upload rejected: JSON decode failed; error=\(error.localizedDescription); bytes=\(request.body.count).")
                return Self.response(400)
            }
            guard !value.files.isEmpty else { DiagnosticLog.write("Prepare upload rejected: no files."); return Self.response(400) }
            DiagnosticLog.write("Prepare upload received: sender=\(value.info.alias); files=\(value.files.count).")
            let id = UUID().uuidString.lowercased(); let accepted = await withCheckedContinuation { continuation in
                queue.async { self.pending[id] = continuation; self.onIncomingTransfer?(IncomingTransfer(id: id, sender: value.info, files: value.files)) }
            }
            guard accepted else { return Self.response(403) }
            let tokens = Dictionary(uniqueKeysWithValues: value.files.keys.map { ($0, UUID().uuidString.lowercased()) }); self.tokens[id] = tokens; self.fileNames[id] = value.files.mapValues(\.fileName)
            return Self.response(200, try? JSONEncoder().encode(PrepareUploadResponse(sessionId: id, files: tokens)))
        }
        if request.method == "POST", request.path.hasPrefix("/api/aiyue/v1/upload") {
            guard let query = URLComponents(string: "http://local" + request.path)?.queryItems, let sessionID = query.first(where: { $0.name == "sessionId" })?.value, let fileID = query.first(where: { $0.name == "fileId" })?.value, let token = query.first(where: { $0.name == "token" })?.value, tokens[sessionID]?[fileID] == token else { return Self.response(401) }
            let fileName = fileNames[sessionID]?[fileID] ?? fileID
            let target = destination.appendingPathComponent(sessionID).appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)
            do { try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try request.body.write(to: target, options: .atomic); return Self.response(204) } catch { return Self.response(500) }
        }
        return Self.response(404)
    }

    private struct HTTPRequest { let method: String; let path: String; let headers: [String: String]; let body: Data }
    private static func parse(_ data: Data) -> HTTPRequest? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)), let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n"); guard let first = lines.first?.split(separator: " "), first.count >= 2 else { return nil }
        var headers: [String: String] = [:]; for line in lines.dropFirst() { let parts = line.split(separator: ":", maxSplits: 1); if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) } }
        let count = Int(headers["content-length"] ?? "0") ?? 0; let start = boundary.upperBound; guard data.count >= start + count else { return nil }
        return HTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(data[start..<start + count]))
    }
    private static func response(_ status: Int, _ body: Data? = nil) -> Data { let value = body ?? Data(); return Data("HTTP/1.1 \(status) OK\r\nContent-Length: \(value.count)\r\nConnection: close\r\n\r\n".utf8) + value }
}
