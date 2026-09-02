import Foundation
import Network

public final class BonjourDeviceBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.luolihao.aiyuetransfer.discovery")
    private var browser: NWBrowser?
    public var onDevicesChanged: (@Sendable ([NearbyDevice]) -> Void)?

    public init() { }
    public func start() {
        queue.async {
            guard self.browser == nil else { return }
            let browser = NWBrowser(for: .bonjour(type: "_aiyue._tcp", domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let devices = results.compactMap { result -> NearbyDevice? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return NearbyDevice(id: name, alias: name, deviceType: "desktop", serviceName: name, serviceType: "_aiyue._tcp", serviceDomain: "local.")
                }
                self?.onDevicesChanged?(devices.sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending })
            }
            browser.stateUpdateHandler = { _ in }
            self.browser = browser; browser.start(queue: self.queue)
        }
    }
    public func stop() { queue.async { self.browser?.cancel(); self.browser = nil } }
}
