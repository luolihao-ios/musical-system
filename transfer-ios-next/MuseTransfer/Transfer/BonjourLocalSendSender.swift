import Foundation
import Network

public final class BonjourLocalSendSender: @unchecked Sendable {
    public init() { }
    public func send(files urls: [URL], to device: NearbyDevice, local: DeviceInfo) async throws {
        let files = try urls.reduce(into: [String: FileMetadata]()) { result, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]); let id = UUID().uuidString.lowercased()
            result[id] = FileMetadata(id: id, fileName: url.lastPathComponent, size: Int64(values.fileSize ?? 0), fileType: values.contentType?.preferredMIMEType ?? "application/octet-stream")
        }
        let prepared = try await request(path: "/api/localsend/v2/prepare-upload", body: JSONEncoder().encode(PrepareUploadRequest(info: local, files: files)), device: device)
        guard prepared.0 != 403, (200..<300).contains(prepared.0) else { throw LocalSendSenderError.rejected }
        let response = try JSONDecoder().decode(PrepareUploadResponse.self, from: prepared.1)
        for (id, file) in files {
            guard let token = response.files[id], let source = urls.first(where: { $0.lastPathComponent == file.fileName }) else { throw LocalSendSenderError.invalidResponse }
            let result = try await request(path: "/api/localsend/v2/upload?sessionId=\(response.sessionId)&fileId=\(id)&token=\(token)", body: Data(contentsOf: source), device: device)
            guard (200..<300).contains(result.0) else { throw LocalSendSenderError.invalidResponse }
        }
    }
    private func request(path: String, body: Data, device: NearbyDevice) async throws -> (Int, Data) {
        let connection = NWConnection(to: .service(name: device.serviceName, type: device.serviceType, domain: device.serviceDomain, interface: nil), using: .tcp)
        let bytes = Data("POST \(path) HTTP/1.1\r\nHost: aiyue\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
        return try await withCheckedThrowingContinuation { continuation in
            var data = Data(); var finished = false
            func finish(_ result: Result<(Int, Data), Error>) { guard !finished else { return }; finished = true; connection.cancel(); continuation.resume(with: result) }
            func receive() { connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { chunk, _, complete, error in if let chunk { data.append(chunk) }; if let error { finish(.failure(error)); return }; if complete { guard let boundary = data.range(of: Data("\r\n\r\n".utf8)), let head = String(data: data[..<boundary.lowerBound], encoding: .utf8), let status = Int(head.split(separator: " ")[1]) else { finish(.failure(LocalSendSenderError.invalidResponse)); return }; finish(.success((status, Data(data[boundary.upperBound...])))) } else { receive() } } }
            connection.stateUpdateHandler = { state in if case .ready = state { connection.send(content: bytes, completion: .contentProcessed { error in if let error { finish(.failure(error)) } else { receive() } }) }; if case let .failed(error) = state { finish(.failure(error)) } }
            connection.start(queue: .global())
        }
    }
}
