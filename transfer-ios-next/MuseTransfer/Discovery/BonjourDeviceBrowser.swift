import Foundation
import Network

public final class BonjourDeviceBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.aiyuetransfer.discovery")
    private let localFingerprintPrefix: String
    private var browser: NWBrowser?
    public var onDevicesChanged: (@Sendable ([NearbyDevice]) -> Void)?

    public init(localFingerprint: String) { localFingerprintPrefix = String(localFingerprint.prefix(12)) }
    public func start() {
        queue.async {
            guard self.browser == nil else { return }
            DiagnosticLog.write("Bonjour browser starting (_aiyue._tcp).")
            let browser = NWBrowser(for: .bonjour(type: "_aiyue._tcp", domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, changes in
                guard let self else { return }
                let ownServiceName = "aiyue-" + self.localFingerprintPrefix
                DiagnosticLog.write("Bonjour browse results: count=\(results.count); changes=\(changes.count).")
                let devices = results.compactMap { result -> NearbyDevice? in
                    guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                    if name == ownServiceName {
                        DiagnosticLog.write("Bonjour own service ignored: \(name).")
                        return nil
                    }
                    DiagnosticLog.write("Bonjour service found: name=\(name); type=\(type); domain=\(domain).")
                    return NearbyDevice(id: "\(name).\(domain)", alias: name, deviceType: "附近设备", serviceName: name, serviceType: type, serviceDomain: domain)
                }
                self?.onDevicesChanged?(devices.sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending })
            }
            browser.stateUpdateHandler = { state in DiagnosticLog.write("Bonjour browser state: \(String(describing: state)).") }
            self.browser = browser; browser.start(queue: self.queue)
        }
    }
    public func stop() { queue.async { DiagnosticLog.write("Bonjour browser stopped."); self.browser?.cancel(); self.browser = nil } }
}
