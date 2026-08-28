import Foundation
import Network

public struct NearbyDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let address: NearbyAddress
    public let receiverPublicKey: Data

    public init(id: String, name: String, platform: String, address: NearbyAddress, receiverPublicKey: Data) {
        self.id = id; self.name = name; self.platform = platform
        self.address = address; self.receiverPublicKey = receiverPublicKey
    }
}

public enum NearbyAddress: Equatable, Sendable {
    case bonjour(name: String, type: String, domain: String)
    case manual(TransferEndpoint)
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
            guard case let .service(serviceName, serviceType, serviceDomain, _) = result.endpoint,
                  case let .bonjour(record) = result.metadata,
                  string("v", in: record) == "2",
                  let id = string("id", in: record),
                  let keyText = string("pk", in: record),
                  let key = Data(base64Encoded: keyText), key.count == 65 else { continue }
            devices[id] = NearbyDevice(id: id, name: string("name", in: record) ?? serviceName,
                platform: string("platform", in: record) ?? "unknown",
                address: .bonjour(name: serviceName, type: serviceType, domain: serviceDomain), receiverPublicKey: key)
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
