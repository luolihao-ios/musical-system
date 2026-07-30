import SwiftUI

struct RecordVisual: View {
    @Bindable var model: NowPlayingModel

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !model.isRecordRotating
            )
        ) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 18) / 18 * 360
            ZStack {
                Circle()
                    .fill(PlayerTheme.accent.opacity(0.32))
                    .blur(radius: model.reduceMotion ? 18 : 30)
                    .scaleEffect(model.reduceMotion ? 0.92 : 1.04)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black,
                                Color(red: 0.08, green: 0.075, blue: 0.09)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 180
                        )
                    )
                    .overlay {
                        ForEach(0..<9, id: \.self) { index in
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.045),
                                    lineWidth: 1
                                )
                                .padding(CGFloat(index) * 10 + 12)
                        }
                    }
                    .overlay {
                        ArtworkView(
                            path: model.state.currentTrack?.artworkReference,
                            cornerRadius: 100
                        )
                        .frame(width: 118, height: 118)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.8), lineWidth: 4)
                        }
                    }
                    .overlay {
                        Circle()
                            .fill(PlayerTheme.accent)
                            .frame(width: 15, height: 15)
                    }
                    .rotationEffect(
                        .degrees(model.isRecordRotating ? angle : 0)
                    )
            }
            .animation(
                model.reduceMotion
                    ? nil
                    : .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                value: model.isRecordRotating
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
