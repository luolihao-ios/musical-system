import Foundation
import Network

public struct TransferHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data
}

public enum TransferTransportError: Error {
    case connectionFailed(String)
    case invalidResponse
    case responseTooLarge
    case rejected(Int, String)
}

public final class NWHTTPTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.musetransfer.http")
    public init() {}

    public func send(method: String, path: String, headers: [String: String] = [:], body: Data = Data(),
                     to address: NearbyAddress, maximumResponseBytes: Int = 2 * 1024 * 1024) async throws -> TransferHTTPResponse {
        let endpoint: NWEndpoint
        switch address {
        case let .bonjour(name, type, domain): endpoint = .service(name: name, type: type, domain: domain, interface: nil)
        case let .manual(value): endpoint = .hostPort(host: NWEndpoint.Host(value.host), port: NWEndpoint.Port(rawValue: value.port)!)
        }
        let connection = NWConnection(to: endpoint, using: .tcp)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operation = HTTPClientOperation(connection: connection, maximumBytes: maximumResponseBytes, continuation: continuation)
                operation.start(request: Self.requestBytes(method: method, path: path, headers: headers, body: body), queue: queue)
            }
        } onCancel: { connection.cancel() }
    }

    private static func requestBytes(method: String, path: String, headers: [String: String], body: Data) -> Data {
        var lines = ["\(method) \(path) HTTP/1.1", "Host: muse-transfer", "Connection: close", "Content-Length: \(body.count)"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }
}

private final class HTTPClientOperation: @unchecked Sendable {
    private let connection: NWConnection
    private let maximumBytes: Int
    private var buffer = Data()
    private var completed = false
    private let continuation: CheckedContinuation<TransferHTTPResponse, Error>

    init(connection: NWConnection, maximumBytes: Int, continuation: CheckedContinuation<TransferHTTPResponse, Error>) {
        self.connection = connection; self.maximumBytes = maximumBytes; self.continuation = continuation
    }

    func start(request: Data, queue: DispatchQueue) {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    if let error { finish(.failure(TransferTransportError.connectionFailed(error.localizedDescription))) }
                    else { receive() }
                })
            case let .failed(error): finish(.failure(TransferTransportError.connectionFailed(error.localizedDescription)))
            case .cancelled: finish(.failure(CancellationError()))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            guard buffer.count <= maximumBytes else { return finish(.failure(TransferTransportError.responseTooLarge)) }
            if let error { return finish(.failure(TransferTransportError.connectionFailed(error.localizedDescription))) }
            if let response = try? parseResponse(buffer), response.body.count == expectedBodyLength(buffer) {
                return finish(.success(response))
            }
            if isComplete { finish(.failure(TransferTransportError.invalidResponse)) } else { receive() }
        }
    }

    private func finish(_ result: Result<TransferHTTPResponse, Error>) {
        guard !completed else { return }; completed = true; connection.cancel(); continuation.resume(with: result)
    }

    private func expectedBodyLength(_ data: Data) -> Int {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let text = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return -1 }
        for line in text.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) ?? -1
        }
        return 0
    }

    private func parseResponse(_ data: Data) throws -> TransferHTTPResponse {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let text = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { throw TransferTransportError.invalidResponse }
        let lines = text.components(separatedBy: "\r\n")
        let status = lines[0].split(separator: " ")
        guard status.count >= 2, let code = Int(status[1]) else { throw TransferTransportError.invalidResponse }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let start = boundary.upperBound
        guard data.count >= start + length else { throw TransferTransportError.invalidResponse }
        return TransferHTTPResponse(statusCode: code, headers: headers, body: Data(data[start..<start + length]))
    }
}
