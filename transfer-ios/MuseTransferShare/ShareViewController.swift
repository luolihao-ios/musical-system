import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await copyAttachments(); extensionContext?.completeRequest(returningItems: nil) }
    }
    private func copyAttachments() async {
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.musetransfer")?.appending(path: "ShareInbox", directoryHint: .isDirectory) else { return }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                guard let value = try? await provider.loadItem(forTypeIdentifier: UTType.item.identifier), let source = value as? URL else { continue }
                let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                var target = inbox.appending(path: source.lastPathComponent); var copy = 2
                while FileManager.default.fileExists(atPath: target.path) { target = inbox.appending(path: "\(source.deletingPathExtension().lastPathComponent) (\(copy)).\(source.pathExtension)"); copy += 1 }
                try? FileManager.default.copyItem(at: source, to: target)
            }
        }
    }
}
