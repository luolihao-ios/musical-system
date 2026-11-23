import SwiftUI

struct RecordVisual: View {
    @Bindable var model: NowPlayingModel
    @State private var baseAngle: Double = 0
    @State private var spinStartDate: Date?

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !model.isRecordRotating
            )
        ) { context in
            let elapsed = (model.isRecordRotating ? spinStartDate : nil)
                .map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let displayedAngle = (baseAngle + elapsed * 20).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle()
                    .fill(PlayerTheme.accent.opacity(0.28))
                    .blur(radius: model.reduceMotion ? 16 : 28)
                    .scaleEffect(model.isRecordRotating && !model.reduceMotion ? 1.03 : 0.94)
                    .animation(.easeInOut(duration: 0.6), value: model.isRecordRotating)

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
                                    Color.white.opacity(0.05),
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
                    .rotationEffect(.degrees(displayedAngle))
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
            }
        }
        .onAppear {
            if model.isRecordRotating && spinStartDate == nil {
                spinStartDate = .now
            }
        }
        .onChange(of: model.isRecordRotating) { _, rotating in
            if rotating {
                spinStartDate = .now
            } else {
                if let start = spinStartDate {
                    baseAngle = (baseAngle + max(0, Date().timeIntervalSince(start)) * 20)
                        .truncatingRemainder(dividingBy: 360)
                }
                spinStartDate = nil
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
