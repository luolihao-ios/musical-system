import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UIKit

final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskDirectory: URL
    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 300
        memory.totalCostLimit = 80 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDirectory = caches.appendingPathComponent("AiYueRemoteArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func load(url: URL, maxPixelSize: Int = 600) async -> UIImage? {
        if let hit = cachedImage(for: url) { return hit }

        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = inFlight[url] { return existing }
            let created = Task<UIImage?, Never>(priority: .utility) { [weak self] in
                guard let self else { return nil }
                if let diskImage = self.loadFromDisk(url: url, maxPixelSize: maxPixelSize) {
                    self.storeInMemory(diskImage, for: url)
                    return diskImage
                }
                guard let image = await self.fetchFromNetwork(url: url, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                self.storeInMemory(image, for: url)
                return image
            }
            inFlight[url] = created
            return created
        }

        let result = await task.value
        lock.withLock {
            inFlight[url] = nil
        }
        return result
    }

    private func storeInMemory(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: url.absoluteString as NSString, cost: max(1, cost))
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(name)
    }

    private func loadFromDisk(url: URL, maxPixelSize: Int) -> UIImage? {
        let path = diskURL(for: url)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return decodeThumbnail(from: path, maxPixelSize: maxPixelSize)
    }

    private func fetchFromNetwork(url: URL, maxPixelSize: Int) async -> UIImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              data.count <= 15 * 1024 * 1024 else {
            return nil
        }
        let target = diskURL(for: url)
        try? data.write(to: target, options: .atomic)
        return decodeThumbnail(from: data, maxPixelSize: maxPixelSize)
    }

    private func decodeThumbnail(from fileURL: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(
            fileURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private func makeThumbnail(from source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct CachedRemoteImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 12
    var maxPixelSize: Int = 500
    var placeholderTint: Color = PlayerTheme.accent.opacity(0.14)

    @State private var image: UIImage?

    init(
        url: URL?,
        cornerRadius: CGFloat = 12,
        maxPixelSize: Int = 500,
        placeholderTint: Color = PlayerTheme.accent.opacity(0.14)
    ) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.maxPixelSize = maxPixelSize
        self.placeholderTint = placeholderTint
        if let url, let cached = RemoteImageCache.shared.cachedImage(for: url) {
            _image = State(initialValue: cached)
        } else {
            _image = State(initialValue: nil)
        }
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholderTint
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = RemoteImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            let loaded = await RemoteImageCache.shared.load(url: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                image = loaded
            }
        }
    }
}
