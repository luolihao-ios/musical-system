import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 10
    @State private var loadedImage: UIImage?

    var body: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: path) {
            // 路径变化才解码；面板每帧改变高度时复用已加载图片。
            loadedImage = path.flatMap { ArtworkImageLoader.image(atPath: $0) }
        }
    }
}
