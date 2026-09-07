import Foundation
import Network
import Darwin

struct WebUploadFile: Codable, Identifiable { let id: String; let name: String; let size: Int64 }
struct WebUpload: Codable, Identifiable {
    let id: String
    let files: [WebUploadFile]
    let folder: String
    var state: String = "waiting"
    var saved: [String: String] = [:]
    var progress: [String: Int64] = [:]
}

final class BrowserTransferServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "aiyue.web")
    private let store: WebFileStore
    private let outboundStore: WebFileStore
    private var listener: NWListener?
    private var connections: [UUID: WebHTTPConnection] = [:]
    private var uploads: [String: WebUpload] = [:]
    private var activeFiles: Set<String> = []
    private var outboundStates: [String: String] = [:]
    private var outboundPublished = false
    private var outboundProgress: [String: Double] = [:]
    private var connectionBatches: [UUID: String] = [:]
    private var token = ""
    private var code = ""
    private var attempts = 0
    private let alias: String
    var onReady: ((String, String) -> Void)?
    var onError: ((String) -> Void)?
    var onUpload: ((WebUpload) -> Void)?
    var onOutboundUpdate: ((String, Double, String) -> Void)?
    init(root: URL, alias: String = "iPhone", outboundRoot: URL? = nil) throws {
        store = try WebFileStore(root: root)
        outboundStore = try WebFileStore(root: outboundRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("AiYueBrowserOutbound"))
        self.alias = alias
    }
    func start() { queue.async { self.stopNow(); self.code = String(Int.random(in: 100000...999999)); self.token = UUID().uuidString; self.attempts = 0; self.listen(port: 8080) } }
    func stop() { queue.async { self.stopNow() } }
    private func stopNow() {
        listener?.cancel(); listener = nil
        Array(connections.values).forEach { $0.close() }; connections.removeAll()
        uploads.removeAll(); activeFiles.removeAll(); connectionBatches.removeAll(); outboundStates.removeAll(); outboundProgress.removeAll(); outboundPublished = false; token = ""
        DiagnosticLog.write("Browser server stopped; sessions cleared.")
    }
    private func listen(port: UInt16) {
        do {
            let next = try NWListener(using: .tcp, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
            listener = next
            next.stateUpdateHandler = { [weak self, weak next] state in
                guard let self, let next, self.listener === next else { return }
                if case .ready = state {
                    guard let ip = Self.wifiAddress(), let port = next.port else { self.onError?("未找到 Wi-Fi 地址，请连接同一局域网"); self.stopNow(); return }
                    DiagnosticLog.write("Browser server ready: TCP \(port.rawValue).")
                    self.onReady?("http://\(ip):\(port.rawValue)", self.code)
                }
                if case .failed = state {
                    next.cancel(); self.listener = nil
                    self.onError?("网页服务无法启动：固定端口 8080 可能已被占用，请关闭占用该端口的应用后重试")
                }
            }
            next.newConnectionHandler = { [weak self] socket in self?.accept(socket) }
            next.start(queue: queue)
        } catch { onError?(error.localizedDescription) }
    }
    private func accept(_ socket: NWConnection) {
        guard connections.count < 16 else { socket.cancel(); return }
        let client = WebHTTPConnection(socket, queue: queue)
        connections[client.id] = client
        var reserved: String?
        client.authorize = { [weak self, weak client] request in
            guard let self else { return false }
            if request.method == "GET", ["/", "/app.js", "/style.css"].contains(request.path) { return request.length == 0 }
            if let origin = request.headers["origin"], origin != "http://" + (request.headers["host"] ?? "") { return false }
            if request.path == "/web/session", request.method == "POST" { return request.length <= 1024 && self.attempts < 30 }
            let cookies = request.headers["cookie"]?.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            guard !self.token.isEmpty, cookies.contains("aiyue=" + self.token) else { return false }
            if request.method == "PUT" {
                let parts = request.path.split(separator: "/").map(String.init)
                guard parts.count == 4, parts[0] == "web", parts[1] == "uploads",
                      let batch = self.uploads[parts[2]], batch.state == "accepted",
                      let file = batch.files.first(where: { $0.id == parts[3] }), file.size == request.length,
                      batch.saved[file.id] == nil else { return false }
                let key = batch.id + "/" + file.id
                guard !self.activeFiles.contains(key) else { return false }
                self.activeFiles.insert(key); reserved = key
                if let client { self.connectionBatches[client.id] = batch.id }
                return true
            }
            return request.length <= 1024 * 1024
        }
        client.onClose = { [weak self, weak client] in
            if let reserved { self?.activeFiles.remove(reserved) }
            if let id = client?.id { self?.connections.removeValue(forKey: id); self?.connectionBatches.removeValue(forKey: id) }
        }
        var lastProgress = Date.distantPast
        client.onProgress = { [weak self] bytes in
            guard let self, let reserved else { return }
            let parts = reserved.split(separator: "/").map(String.init)
            guard parts.count == 2, var batch = self.uploads[parts[0]], batch.state == "accepted" else { return }
            batch.progress[parts[1]] = bytes; self.uploads[batch.id] = batch
            if Date().timeIntervalSince(lastProgress) > 0.15 { lastProgress = Date(); self.onUpload?(batch) }
        }
        client.handle = { [weak self] request, body, client in self?.route(request, body: body, client: client) }
        client.start()
    }
    func decide(_ id: String, accepted: Bool) { queue.async {
        guard var batch = self.uploads[id], batch.state == "waiting" else { return }
        batch.state = accepted ? "accepted" : "rejected"; self.uploads[id] = batch
        DiagnosticLog.write("Browser upload decision: \(id); accepted=\(accepted).")
        self.onUpload?(batch)
    } }
    func publishOutbound() { queue.async { self.outboundPublished = true } }
    func clearOutbound() { queue.async { try? self.outboundStore.list("").filter { !$0.directory }.forEach { try? FileManager.default.removeItem(at: try self.outboundStore.resolve($0.path)) }; self.outboundStates.removeAll(); self.outboundProgress.removeAll(); self.outboundPublished = false } }
    private func route(_ request: WebRequest, body: URL, client: WebHTTPConnection) {
        do {
            if request.method == "GET", ["/", "/app.js", "/style.css"].contains(request.path) {
                let name = request.path == "/" ? "index.html" : String(request.path.dropFirst())
                guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "WebAssets") ?? Bundle.main.url(forResource: name, withExtension: nil) else { throw WebFailure.invalidRequest }
                client.reply(200, data: try Data(contentsOf: url), type: name.hasSuffix("html") ? "text/html; charset=utf-8" : name.hasSuffix("js") ? "application/javascript" : "text/css"); return
            }
            if request.path == "/web/session", request.method == "POST" {
                let value = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: body)); attempts += 1
                guard value["code"] == code else { client.reply(403, ["error": "访问码不正确"]); return }
                DiagnosticLog.write("Browser session authenticated.")
                client.reply(200, data: Data("{}".utf8), type: "application/json", extra: "Set-Cookie: aiyue=\(token); HttpOnly; SameSite=Strict; Path=/\r\n"); return
            }
            if request.path == "/web/files", request.method == "GET" { client.reply(200, try store.list(request.query("path"))); return }
            if request.path == "/web/outbound", request.method == "GET" {
                let entries: [BrowserOutboundTask] = self.outboundPublished ? try outboundStore.list("").filter { !$0.directory }.map {
                    BrowserOutboundTask(id: $0.name, name: $0.name, bytes: $0.size, url: $0.path, state: self.outboundStates[$0.name] ?? "waiting", progress: self.outboundProgress[$0.name] ?? 0)
                } : []
                client.reply(200, entries); return
            }
            if request.path == "/web/outbound/publish", request.method == "POST" { outboundPublished = true; client.reply(200, ["ok": true]); return }
            if request.path == "/web/outbound/decision", request.method == "POST" {
                let value = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: body)); let accepted = value["accepted"] == "true"
                let names = try outboundStore.list("").filter { !$0.directory }.map(\.name)
                for name in names { outboundStates[name] = accepted ? "accepted" : "rejected"; if !accepted { try? FileManager.default.removeItem(at: outboundStore.resolve(name)) } }
                client.reply(200, ["ok": true]); return
            }
            if request.path.hasPrefix("/web/outbound/"), request.method == "POST", request.path.hasSuffix("/progress") {
                let raw = String(request.path.dropFirst("/web/outbound/".count).dropLast("/progress".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let value = try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: body)); let progress = min(1, max(0, value["progress"] ?? 0))
                outboundProgress[raw] = progress; outboundStates[raw] = progress >= 1 ? "completed" : "downloading"; onOutboundUpdate?(raw, progress, outboundStates[raw]!); client.reply(200, ["ok": true]); return
            }
            if request.path.hasPrefix("/web/outbound/"), request.method == "POST", request.path.hasSuffix("/decision") {
                let raw = String(request.path.dropFirst("/web/outbound/".count).dropLast("/decision".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let value = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: body))
                let accepted = value["accepted"] == "true"
                guard FileManager.default.fileExists(atPath: try outboundStore.resolve(raw).path) else { throw WebFailure.invalidPath }
                outboundStates[raw] = accepted ? "accepted" : "rejected"
                if !accepted { try? FileManager.default.removeItem(at: outboundStore.resolve(raw)) }
                client.reply(200, ["ok": true]); return
            }
            if request.path == "/web/outbound/download", request.method == "GET" {
                let name = request.query("name")
                client.download(try outboundStore.resolve(name)); return
            }
            if request.path.hasPrefix("/web/outbound/"), request.method == "POST", request.path.hasSuffix("/complete") {
                let raw = String(request.path.dropFirst("/web/outbound/".count).dropLast("/complete".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                outboundStates[raw] = "completed"; outboundProgress[raw] = 1; onOutboundUpdate?(raw, 1, "completed"); client.reply(200, ["ok": true]); return
            }
            if request.path == "/web/info", request.method == "GET" {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                client.reply(200, ["alias": alias, "version": version ?? "1.0"]); return
            }
            if request.path == "/web/diagnostics", request.method == "GET" { client.download(DiagnosticLog.fileURL); return }
            if request.path == "/web/uploads", request.method == "GET" { client.reply(200, Array(uploads.values)); return }
            if request.path == "/web/download", request.method == "GET" { client.download(try store.resolve(request.query("path"))); return }
            if request.path == "/web/folders", request.method == "POST" {
                let value = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: body))
                try store.createFolder(value["path"] ?? ""); client.reply(200, ["ok": true]); return
            }
            if request.path == "/web/uploads", request.method == "POST" {
                guard !uploads.values.contains(where: { ["waiting", "accepted"].contains($0.state) }) else { client.reply(409, ["error": "请先完成或取消上一批传输"]); return }
                let files = try JSONDecoder().decode([WebUploadFile].self, from: Data(contentsOf: body))
                guard !files.isEmpty, files.count <= 1000, Set(files.map(\.id)).count == files.count,
                      files.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.size >= 0 && $0.size <= 100 * 1024 * 1024 * 1024 }) else { throw WebFailure.invalidRequest }
                for file in files { _ = try store.resolve(file.name) }
                let batch = WebUpload(id: UUID().uuidString, files: files, folder: Self.transferFolderName())
                uploads = [batch.id: batch]
                DiagnosticLog.write("Browser upload request received: batch=\(batch.id); files=\(files.count).")
                onUpload?(batch); client.reply(200, batch)
                queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                    guard var pending = self?.uploads[batch.id], pending.state == "waiting" else { return }
                    pending.state = "expired"; self?.uploads[batch.id] = pending; self?.onUpload?(pending)
                }; return
            }
            let parts = request.path.split(separator: "/").map(String.init)
            if parts.count >= 3, parts[0] == "web", parts[1] == "uploads", var batch = uploads[parts[2]] {
                if request.method == "GET", parts.count == 3 { client.reply(200, batch); return }
                if request.method == "DELETE", parts.count == 3 {
                    batch.state = "cancelled"; uploads[batch.id] = batch
                    let ids = connectionBatches.filter { $0.value == batch.id }.map(\.key)
                    for id in ids { connections[id]?.close() }
                    onUpload?(batch); client.reply(200, batch); return
                }
                if request.method == "PUT", parts.count == 4, batch.state == "accepted", let file = batch.files.first(where: { $0.id == parts[3] }) {
                    let name = URL(fileURLWithPath: file.name).lastPathComponent
                    batch.saved[file.id] = try store.save(body, as: batch.folder + "/" + name)
                    if batch.saved.count == batch.files.count { batch.state = "completed" }
                    uploads[batch.id] = batch; onUpload?(batch)
                    DiagnosticLog.write("Browser file saved: batch=\(batch.id); bytes=\(file.size).")
                    client.reply(200, batch); return
                }
            }
            client.reply(404, ["error": "找不到此请求"])
        } catch {
            DiagnosticLog.write("Browser request failed: \(request.method) \(request.path); \(error.localizedDescription)")
            client.reply(400, ["error": "操作失败，请检查文件名、存储空间或重新连接"])
        }
    }
    static func wifiAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }; defer { freeifaddrs(interfaces) }
        var cursor = interfaces
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == "en0", let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
        }
        return nil
    }

    private static func transferFolderName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
