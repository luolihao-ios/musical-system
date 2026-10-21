import MediaPlayer
import UIKit

// 不在 @MainActor 上下文中创建系统回调。MediaPlayer 可以从后台线程调用它们。
enum SystemMediaCallbacks {
    // CGImage 是只读像素快照；只在这个边界声明跨线程共享，不传递可变 UI 状态。
    private struct Pixels: @unchecked Sendable { let image: CGImage }

    static func artwork(image: CGImage) -> MPMediaItemArtwork {
        let pixels = Pixels(image: image)
        return MPMediaItemArtwork(boundsSize: CGSize(width: image.width, height: image.height)) { _ in
            PlaybackDiagnostics.log("系统封面回调 enter main=\(Thread.isMainThread)")
            let result = UIImage(cgImage: pixels.image)
            PlaybackDiagnostics.log("系统封面回调 exit")
            return result
        }
    }

    static func command(_ action: @escaping @MainActor @Sendable () async -> Void)
        -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { _ in Task { await action() }; return .success }
    }

    static func seek(_ action: @escaping @MainActor @Sendable (TimeInterval) async -> Void)
        -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { await action(position) }
            return .success
        }
    }
}
