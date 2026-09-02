import Foundation
import SwiftUI
import Observation
import UIKit

@Observable final class TransferViewModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [URL] = []
    var showImporter = false
    var selectedSummary: String { selectedFiles.isEmpty ? "尚未选择文件" : "已选择 \(selectedFiles.count) 个文件" }
    func refresh() { }
    func select(_ result: Result<[URL], Error>) { if case let .success(urls) = result { selectedFiles = urls } }
    func send(to device: NearbyDevice) {
        guard !selectedFiles.isEmpty else { return }
        Task { try? await LocalSendSender().send(files: selectedFiles, to: device.endpoint, local: DeviceInfo(alias: UIDevice.current.name, deviceModel: "iPhone", deviceType: "mobile", fingerprint: UUID().uuidString)) }
    }
}

struct NearbyDevice: Identifiable, Hashable { let id: String; let alias: String; let deviceType: String; let endpoint: URL }
