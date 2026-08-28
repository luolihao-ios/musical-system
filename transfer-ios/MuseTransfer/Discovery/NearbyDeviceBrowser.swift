import Foundation
import Network

public struct NearbyDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let endpoint: TransferEndpoint
    public let receiverPublicKey: Data

    public init(id: String, name: String, platform: String, endpoint: TransferEndpoint, receiverPublicKey: Data) {
        self.id = id; self.name = name; self.platform = platform
        self.endpoint = endpoint; self.receiverPublicKey = receiverPublicKey
    }
}

public final class NearbyDeviceBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.musetransfer.browser")
    private var browser: NWBrowser?
    private var continuation: AsyncStream<[NearbyDevice]>.Continuation?
    private var current: [String: NearbyDevice] = [:]

    public init() {}

    public func devices() -> AsyncStream<[NearbyDevice]> {
        AsyncStream { continuation in
            queue.async {
                self.continuation?.finish()
                self.continuation = continuation
                continuation.yield(Array(self.current.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                continuation.onTermination = { [weak self] _ in self?.stop() }
                self.startIfNeeded()
            }
        }
    }

    public func stop() {
        queue.async {
            self.browser?.cancel(); self.browser = nil
            self.current.removeAll(); self.continuation?.finish(); self.continuation = nil
        }
    }

    private func startIfNeeded() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_musetransfer._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in self?.replace(with: results) }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.browser?.cancel(); self?.browser = nil }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func replace(with results: Set<NWBrowser.Result>) {
        var devices: [String: NearbyDevice] = [:]
        for result in results {
            guard case let .service(serviceName, _, _, _) = result.endpoint,
                  case let .bonjour(record) = result.metadata,
                  string("v", in: record) == "2",
                  let id = string("id", in: record),
                  let keyText = string("pk", in: record),
                  let key = Data(base64Encoded: keyText), key.count == 65 else { continue }
            // NWConnection resolves the Bonjour service endpoint. The displayed port is replaced during connection.
            guard let placeholder = try? TransferEndpoint(host: serviceName, port: 1) else { continue }
            devices[id] = NearbyDevice(id: id, name: string("name", in: record) ?? serviceName,
                platform: string("platform", in: record) ?? "unknown", endpoint: placeholder, receiverPublicKey: key)
        }
        current = devices
        continuation?.yield(Array(devices.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func string(_ key: String, in record: NWTXTRecord) -> String? {
        guard let entry = record.getEntry(for: key) else { return nil }
        switch entry {
        case let .string(value): return value
        case let .data(value): return String(data: value, encoding: .utf8)
        case .empty: return ""
        case .none: return nil
        @unknown default: return nil
        }
    }
}
