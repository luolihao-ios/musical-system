import SwiftUI

struct PlaybackWaveformView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 18.0,
                paused: !isPlaying
            )
        ) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<twentyFourBars, id: \.self) { index in
                    let phase = time * 4.2 + Double(index) * 0.48
                    let amplitude = isPlaying
                        ? (0.25 + abs(sin(phase)) * 0.75)
                        : 0.24
                    Capsule()
                        .fill(PlayerTheme.accent.opacity(isPlaying ? 0.9 : 0.45))
                        .frame(width: 3, height: CGFloat(5 + amplitude * 20))
                }
            }
            .frame(height: 28)
            .animation(.easeInOut(duration: 0.16), value: isPlaying)
        }
        .accessibilityLabel(isPlaying ? "正在播放，声波动态" : "播放已暂停")
    }

    private var twentyFourBars: Int { 24 }
}
