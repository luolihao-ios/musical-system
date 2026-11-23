import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 10
    @State private var loadedImage: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                Group {
                    if let image = loadedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    PlayerTheme.panel,
                                    PlayerTheme.accent.opacity(0.42)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        .task(id: path) {
            guard let path, !path.isEmpty else {
                loadedImage = nil
                return
            }
            if (path.hasPrefix("https://") || path.hasPrefix("http://")), let url = URL(string: path) {
                if let cached = RemoteImageCache.shared.cachedImage(for: url) {
                    loadedImage = cached
                } else {
                    let fetched = await RemoteImageCache.shared.load(url: url, maxPixelSize: 600)
                    guard !Task.isCancelled else { return }
                    loadedImage = fetched
                }
            } else {
                // 路径变化才解码；面板每帧改变高度时复用已加载图片。
                loadedImage = ArtworkImageLoader.image(atPath: path)
            }
        }
    }
}
