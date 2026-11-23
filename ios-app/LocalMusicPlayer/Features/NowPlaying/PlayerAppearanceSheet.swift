import SwiftUI

struct PlayerAppearanceSheet: View {
    @Binding var visualMode: PlayerVisualMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择播放页外观，随时可切换")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                PlayerSkinCardsRow(visualMode: $visualMode) {
                    dismiss()
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("播放器外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.42), .medium])
        .presentationDragIndicator(.visible)
    }
}

struct PlayerSkinCardsRow: View {
    @Binding var visualMode: PlayerVisualMode
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PlayerVisualMode.allCases) { mode in
                let selected = visualMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visualMode = mode
                    }
                    onSelect?()
                } label: {
                    VStack(spacing: 10) {
                        previewGraphic(for: mode)
                            .frame(height: 112)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selected ? PlayerTheme.accent : Color.clear, lineWidth: 2.5)
                            }
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(PlayerTheme.accent)
                                        .background(Color.white, in: Circle())
                                        .padding(6)
                                }
                            }

                        Text(mode.title)
                            .font(.caption.weight(selected ? .bold : .medium))
                            .foregroundStyle(selected ? PlayerTheme.accent : .primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("player.skin.\(mode.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func previewGraphic(for mode: PlayerVisualMode) -> some View {
        switch mode {
        case .cover:
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, PlayerTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 54, height: 4)
            }
        case .vinyl:
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 68, height: 68)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 1).padding(8)
                    }
                    .overlay {
                        Circle()
                            .fill(PlayerTheme.accent.gradient)
                            .frame(width: 24, height: 24)
                    }
                    .overlay {
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                    }
                Capsule()
                    .fill(Color.gray)
                    .frame(width: 4, height: 34)
                    .rotationEffect(.degrees(28))
                    .offset(x: 24, y: -14)
            }
        case .classic:
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.90, green: 0.95, blue: 0.92))
                    .frame(width: 44, height: 30)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.25), lineWidth: 1)
                    }
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    Circle()
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(red: 0.80, green: 0.82, blue: 0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
