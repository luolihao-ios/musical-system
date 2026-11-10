import SwiftUI

struct VinylTonearm: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Path { path in
                path.move(to: CGPoint(x: size.width * 0.76, y: size.height * 0.10))
                path.addQuadCurve(to: CGPoint(x: size.width * 0.28, y: size.height * 0.92),
                                  control: CGPoint(x: size.width * 0.91, y: size.height * 0.58))
            }
            .stroke(.linearGradient(colors: [.white, .gray, .white], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().fill(Color.gray.gradient).frame(width: 24, height: 24)
                .position(x: size.width * 0.76, y: size.height * 0.1)
            Capsule().fill(.white).frame(width: 11, height: 24).rotationEffect(.degrees(38))
                .position(x: size.width * 0.28, y: size.height * 0.92)
        }
    }
}

struct ClassicPlayerVisual: View {
    @Bindable var model: NowPlayingModel
    let showQueue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * 0.83)
            let wheel = width * 0.53
            VStack(spacing: width * 0.04) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在播放").font(.caption.bold())
                    HStack(spacing: 7) {
                        ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 5)
                            .frame(width: width * 0.18, height: width * 0.18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.state.currentTrack?.title ?? "").font(.caption.bold()).lineLimit(1)
                            Text(model.state.currentTrack?.artist ?? "").font(.caption2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    ProgressView(value: model.progress)
                        .tint(PlayerTheme.accent)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.93, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.black)
                ZStack {
                    Circle().fill(Color.white.gradient).shadow(color: .black.opacity(0.18), radius: 3)
                    Button { Task { await model.togglePlayback() } } label: {
                        Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: wheel * 0.43, height: wheel * 0.43)
                            .background(.gray.opacity(0.23), in: Circle())
                    }
                    VStack {
                        Button(action: showQueue) { Text("MENU").font(.caption2.bold()).padding(5) }
                        Spacer(minLength: 0)
                        HStack {
                            Button { Task { await model.previous() } } label: {
                                Image(systemName: "backward.end.fill").padding(6)
                            }.accessibilityLabel("上一首")
                            Spacer(minLength: 0)
                            Button { Task { await model.next() } } label: {
                                Image(systemName: "forward.end.fill").padding(6)
                            }.accessibilityLabel("下一首")
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "music.note").font(.caption2).padding(5).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .frame(width: wheel, height: wheel)
            }
            .padding(width * 0.06)
            .frame(width: width)
            .background(Color(red: 0.78, green: 0.80, blue: 0.82).gradient, in: RoundedRectangle(cornerRadius: 22))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
