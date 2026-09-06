import Foundation
import Network

struct WebRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let length: Int64
    var components: URLComponents? { URLComponents(string: "http://local" + target) }
    var path: String { components?.path ?? "" }
    func query(_ name: String) -> String { components?.queryItems?.first { $0.name == name }?.value ?? "" }
}

// One request per connection; body and downloads are streamed in bounded chunks.
final class WebHTTPConnection {
    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let temporary: URL
    private var buffer = Data()
    private var request: WebRequest?
    private var output: FileHandle?
    private var input: FileHandle?
    private var received: Int64 = 0
    private var deadline: DispatchWorkItem?
    private var closed = false
    private var responding = false
    var authorize: ((WebRequest) -> Bool)?
    var handle: ((WebRequest, URL, WebHTTPConnection) -> Void)?
    var onClose: (() -> Void)?
    var onProgress: ((Int64) -> Void)?
    init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection; self.queue = queue
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString)")
    }
    func start() { connection.start(queue: queue); read() }
    func close() {
        guard !closed else { return }; closed = true
        deadline?.cancel(); try? output?.close(); try? input?.close()
        output = nil; input = nil
        try? FileManager.default.removeItem(at: temporary)
        connection.cancel(); onClose?()
    }
    private func touch() {
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        deadline = work; queue.asyncAfter(deadline: .now() + 60, execute: work)
    }
    private func read() {
        touch()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] bytes, _, complete, error in
            guard let self, !self.closed else { return }
            if error != nil { self.close(); return }
            do {
                if let bytes { try self.consume(bytes) }
                guard !self.closed, !self.responding else { return }
                if let request = self.request, self.received == request.length {
                    try self.output?.close(); self.output = nil
                    self.handle?(request, self.temporary, self)
                } else if complete { self.close() } else { self.read() }
            } catch { self.reply(400, ["error": "请求格式或文件大小无效"]); }
        }
    }
    private func consume(_ bytes: Data) throws {
        if request == nil {
            buffer.append(bytes)
            guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 16384 { throw WebFailure.invalidRequest }; return
            }
            guard boundary.lowerBound <= 16384, let text = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else { throw WebFailure.invalidRequest }
            let lines = text.components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count == 3, first[1].hasPrefix("/"), !first[1].hasPrefix("//") else { throw WebFailure.invalidRequest }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let pair = line.split(separator: ":", maxSplits: 1)
                guard pair.count == 2 else { throw WebFailure.invalidRequest }
                let key = pair[0].lowercased()
                guard headers[key] == nil else { throw WebFailure.invalidRequest }
                headers[key] = pair[1].trimmingCharacters(in: .whitespaces)
            }
            guard headers["transfer-encoding"] == nil,
                  let length = Int64(headers["content-length"] ?? "0"), length >= 0 else { throw WebFailure.invalidRequest }
            let parsed = WebRequest(method: String(first[0]), target: String(first[1]), headers: headers, length: length)
            guard authorize?(parsed) == true else { reply(403, ["error": "会话失效、尚未接受或请求无效"]); return }
            request = parsed
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw WebFailure.invalidRequest }
            output = try FileHandle(forWritingTo: temporary)
            let body = Data(buffer[boundary.upperBound...]); buffer.removeAll()
            try write(body)
        } else { try write(bytes) }
    }
    private func write(_ bytes: Data) throws {
        guard let request, received + Int64(bytes.count) <= request.length else { throw WebFailure.invalidRequest }
        try output?.write(contentsOf: bytes); received += Int64(bytes.count); onProgress?(received)
    }
    func reply<T: Encodable>(_ status: Int, _ value: T) {
        reply(status, data: (try? JSONEncoder().encode(value)) ?? Data(), type: "application/json; charset=utf-8")
    }
    func reply(_ status: Int, data: Data, type: String, extra: String = "") {
        guard !closed, !responding else { return }; responding = true; touch()
        connection.send(content: header(status, count: Int64(data.count), type: type, extra: extra) + data, completion: .contentProcessed { [weak self] _ in self?.close() })
    }
    func download(_ url: URL) {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true else { throw WebFailure.invalidRequest }
            input = try FileHandle(forReadingFrom: url)
            responding = true
            let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file"
            connection.send(content: header(200, count: Int64(size.fileSize ?? 0), type: "application/octet-stream", extra: "Content-Disposition: attachment; filename*=UTF-8''\(name)\r\n"), completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close() } else { self?.sendChunk() }
            })
        } catch { reply(404, ["error": "文件不存在或不可读取"]) }
    }
    private func sendChunk() {
        guard !closed else { return }; touch()
        do {
            guard let bytes = try input?.read(upToCount: 64 * 1024), !bytes.isEmpty else { close(); return }
            connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close() } else { self?.sendChunk() }
            })
        } catch { close() }
    }
    private func header(_ status: Int, count: Int64, type: String, extra: String) -> Data {
        Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Response")\r\nContent-Length: \(count)\r\nContent-Type: \(type)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; frame-ancestors 'none'\r\n\(extra)Connection: close\r\n\r\n".utf8)
    }
}
