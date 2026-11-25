import SwiftUI
import UIKit

struct VinylTonearm: View {
    var isPlaying: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.76, y: size.height * 0.10))
                    path.addQuadCurve(
                        to: CGPoint(x: size.width * 0.28, y: size.height * 0.90),
                        control: CGPoint(x: size.width * 0.90, y: size.height * 0.56)
                    )
                }
                .stroke(
                    .linearGradient(colors: [.white, .gray, .white], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                Capsule()
                    .fill(.white)
                    .frame(width: 11, height: 24)
                    .rotationEffect(.degrees(38))
                    .position(x: size.width * 0.28, y: size.height * 0.90)
                Circle()
                    .fill(Color.gray.gradient)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle().stroke(.white.opacity(0.6), lineWidth: 1.5)
                    }
                    .position(x: size.width * 0.76, y: size.height * 0.10)
            }
            .rotationEffect(
                .degrees(isPlaying ? 0 : -24),
                anchor: UnitPoint(x: 0.76, y: 0.10)
            )
            .animation(.easeInOut(duration: 0.35), value: isPlaying)
        }
    }
}

private struct ClickWheelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ClassicPlayerVisual: View {
    static var chassisBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.90, green: 0.91, blue: 0.93),
                Color(red: 0.78, green: 0.80, blue: 0.83)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private enum ScreenMode: CaseIterable {
        case nowPlaying
        case queue
        case lyrics

        var title: String {
            switch self {
            case .nowPlaying: String(localized: "正在播放")
            case .queue: String(localized: "播放队列")
            case .lyrics: String(localized: "歌词")
            }
        }

        var next: Self {
            switch self {
            case .nowPlaying: .queue
            case .queue: .lyrics
            case .lyrics: .nowPlaying
            }
        }
    }

    @Bindable var model: NowPlayingModel
    let showQueue: () -> Void
    var isFullScreen: Bool = false
    var bottomSafeInset: CGFloat = 0
    var onLongPressArtwork: (() -> Void)? = nil
    @State private var screenMode: ScreenMode = .nowPlaying
    @State private var lastWheelAngle: Double?
    @State private var wheelDeltaAccumulator: Double = 0

    var body: some View {
        GeometryReader { geometry in
            if isFullScreen {
                let wheelDiameter = min(geometry.size.width * 0.72, geometry.size.height * 0.44, 276)
                VStack(spacing: 22) {
                    ipodScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    clickWheel(diameter: wheelDiameter)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, max(24, bottomSafeInset + 12))
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else if AdaptivePlayerLayout.isTabletopCompactPane(size: geometry.size) {
                let bodyWidth = min(max(geometry.size.width - 20, 320), 620)
                let bodyHeight = min(max(geometry.size.height - 12, 220), 340)
                let wheelDiameter = min(bodyHeight - 28, bodyWidth * 0.42, 220)

                HStack(spacing: 16) {
                    ipodScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    clickWheel(diameter: wheelDiameter)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(width: bodyWidth, height: bodyHeight)
                .background(
                    Self.chassisBackground,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.65), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let bodyWidth = min(max(geometry.size.width - 24, 220), 420)
                let maxH = max(geometry.size.height - 12, 260)
                let bodyHeight = min(maxH, 660)
                let wheelDiameter = min(bodyWidth * 0.66, bodyHeight * 0.42, 240)

                VStack(spacing: 18) {
                    ipodScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    clickWheel(diameter: wheelDiameter)
                        .padding(.bottom, 6)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(width: bodyWidth, height: bodyHeight)
                .background(
                    Self.chassisBackground,
                    in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.65), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var ipodScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: model.state.isPlaying ? "play.fill" : "pause.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(PlayerTheme.accent)
                Text(screenMode.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let index = model.state.currentIndex, !model.state.queue.isEmpty {
                    Text("\(index + 1)/\(model.state.queue.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: modeIcon)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.06))

            Divider()

            Group {
                switch screenMode {
                case .nowPlaying:
                    nowPlayingLCD
                case .queue:
                    queueLCD
                case .lyrics:
                    lyricsLCD
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Color(red: 0.10, green: 0.13, blue: 0.15))
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.97, blue: 0.95),
                    Color(red: 0.89, green: 0.94, blue: 0.91)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.25), lineWidth: 2)
        }
    }

    private var nowPlayingLCD: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 4)
            HStack(spacing: 14) {
                ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 10)
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                    .onLongPressGesture(minimumDuration: 0.45) {
                        haptic()
                        onLongPressArtwork?()
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.state.currentTrack?.title ?? String(localized: "爱乐之城"))
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                    Text(model.state.currentTrack?.artist ?? String(localized: "本地播放"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let album = model.state.currentTrack?.album, !album.isEmpty {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if let snippet = NowPlayingLyricSnippet.lines(from: model.lyricLines, currentIndex: model.currentLyricIndex).first {
                Text(snippet.text)
                    .font(.caption)
                    .foregroundStyle(PlayerTheme.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer(minLength: 4)
            VStack(spacing: 5) {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.12))
                        Capsule()
                            .fill(PlayerTheme.accent)
                            .frame(width: bar.size.width * model.progress)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text(format(model.state.position))
                    Spacer()
                    Text(format(model.state.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var queueLCD: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(model.state.queue.enumerated()), id: \.element.id) { entry in
                    let isCurrent = entry.offset == model.state.currentIndex
                    Button {
                        Task { await model.playQueueItem(at: entry.offset) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                                .font(.caption2)
                            Text(entry.element.title)
                                .font(.caption.weight(isCurrent ? .bold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(entry.element.artist)
                                .font(.caption2)
                                .lineLimit(1)
                                .opacity(0.75)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(isCurrent ? .white : Color(red: 0.10, green: 0.13, blue: 0.15))
                        .background(isCurrent ? PlayerTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var lyricsLCD: some View {
        Group {
            if model.hasLyrics {
                SyncedLyricsView(model: model, foreground: Color(red: 0.10, green: 0.13, blue: 0.15))
                    .padding(.horizontal, 12)
            } else {
                VStack(spacing: 8) {
                    Text("暂无歌词").font(.subheadline.weight(.semibold))
                    Button {
                        Task { await model.findLyrics() }
                    } label: {
                        Label(model.isSearchingLyrics ? String(localized: "正在查找歌词…") : String(localized: "查找歌词"), systemImage: "text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(PlayerTheme.accent)
                    .disabled(model.isSearchingLyrics)
                }
                .padding()
            }
        }
    }

    private func clickWheel(diameter: CGFloat) -> some View {
        let centerDiameter = diameter * 0.36
        let ringForeground = Color(red: 0.36, green: 0.38, blue: 0.42)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.94, green: 0.95, blue: 0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .overlay {
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 1)
                }

            ZStack {
                Button {
                    haptic()
                    screenMode = screenMode.next
                    if screenMode == .lyrics && !model.hasLyrics && !model.isSearchingLyrics {
                        Task { await model.findLyrics() }
                    }
                } label: {
                    Text("MENU")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .frame(width: diameter * 0.46, height: diameter * 0.28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("切换 iPod 菜单")
                .accessibilityIdentifier("ipod.menu")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Button {
                    haptic()
                    Task { await model.previous() }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.body.weight(.bold))
                        .frame(width: diameter * 0.30, height: diameter * 0.44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("上一首")
                .accessibilityIdentifier("ipod.previous")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Button {
                    haptic()
                    Task { await model.next() }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body.weight(.bold))
                        .frame(width: diameter * 0.30, height: diameter * 0.44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("下一首")
                .accessibilityIdentifier("ipod.next")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                Button {
                    haptic()
                    Task { await model.togglePlayback() }
                } label: {
                    Image(systemName: "playpause.fill")
                        .font(.body.weight(.bold))
                        .frame(width: diameter * 0.46, height: diameter * 0.28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.state.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
                .accessibilityIdentifier("ipod.playPause")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .foregroundStyle(ringForeground)
            .clipShape(Circle())

            Button {
                haptic()
                if screenMode == .nowPlaying {
                    model.cycleMode()
                } else {
                    screenMode = .nowPlaying
                }
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.87, blue: 0.89),
                                Color(red: 0.77, green: 0.79, blue: 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: centerDiameter, height: centerDiameter)
                    .contentShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            }
            .accessibilityLabel(screenMode == .nowPlaying ? String(localized: "切换播放模式") : String(localized: "返回正在播放"))
            .accessibilityIdentifier("ipod.center")
        }
        .buttonStyle(ClickWheelButtonStyle())
        .simultaneousGesture(wheelScrubGesture(diameter: diameter))
        .frame(width: diameter, height: diameter)
    }

    private func wheelScrubGesture(diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let distance = hypot(dx, dy)
                guard distance > diameter * 0.2 else { return }
                let angle = atan2(dy, dx)
                if let previous = lastWheelAngle {
                    var delta = angle - previous
                    if delta > .pi { delta -= 2 * .pi }
                    if delta < -.pi { delta += 2 * .pi }
                    wheelDeltaAccumulator += delta
                    if abs(wheelDeltaAccumulator) >= 0.22 {
                        let step = wheelDeltaAccumulator > 0 ? 5.0 : -5.0
                        wheelDeltaAccumulator = 0
                        if model.state.duration > 0 {
                            let target = (model.state.position + step) / model.state.duration
                            try? model.seek(fraction: target)
                            haptic()
                        }
                    }
                }
                lastWheelAngle = angle
            }
            .onEnded { _ in
                lastWheelAngle = nil
                wheelDeltaAccumulator = 0
            }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var modeIcon: String {
        switch model.state.mode {
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = max(Int(seconds), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
