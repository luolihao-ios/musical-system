import SwiftUI

struct NowPlayingView: View {
    @Bindable var model: NowPlayingModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.07, blue: 0.11),
                        PlayerTheme.background,
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 22) {
                            RecordVisual(model: model)
                                .frame(
                                    width: min(geometry.size.width - 64, 340),
                                    height: min(geometry.size.width - 64, 340)
                                )
                                .padding(.top, 12)
                            trackIdentity
                            if model.hasLyrics {
                                SyncedLyricsView(model: model)
                                    .frame(height: 210)
                            } else {
                                noLyrics
                            }
                            progressControls
                            transportControls
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("播放队列")
                }
            }
        }
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in
            model.reduceMotion = value
        }
        .sheet(isPresented: $showQueue) {
            queueSheet
        }
    }

    private var trackIdentity: some View {
        VStack(spacing: 6) {
            Text(model.state.currentTrack?.title ?? "选择一首本地音乐")
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Text(model.state.currentTrack?.artist ?? "暮色音乐")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var noLyrics: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.system(size: 38))
                .foregroundStyle(PlayerTheme.accent)
            Text("这一刻没有同步歌词")
                .font(.headline)
            Text("让唱片和光影陪音乐继续旋转")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
    }

    private var progressControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { model.progress },
                    set: { try? model.seek(fraction: $0) }
                ),
                in: 0...1
            )
            .tint(PlayerTheme.accent)
            .accessibilityLabel("播放进度")
            HStack {
                Text(format(model.state.position))
                Spacer()
                Text(format(model.state.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 34) {
            Button {
                Task { await model.previous() }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("上一首")

            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(
                    systemName: model.state.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                )
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(PlayerTheme.accent, in: Circle())
                .foregroundStyle(.white)
            }
            .accessibilityLabel(model.state.isPlaying ? "暂停" : "播放")

            Button {
                Task { await model.next() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
    }

    private var queueSheet: some View {
        NavigationStack {
            List(
                Array(model.state.queue.enumerated()),
                id: \.element.id
            ) { index, track in
                HStack {
                    Image(
                        systemName: index == model.state.currentIndex
                            ? "speaker.wave.2.fill"
                            : "music.note"
                    )
                    .foregroundStyle(
                        index == model.state.currentIndex
                            ? PlayerTheme.accent
                            : Color.secondary
                    )
                    VStack(alignment: .leading) {
                        Text(track.title)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = max(Int(seconds), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
