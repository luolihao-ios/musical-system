import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Item: Equatable, Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String?
    }

    private(set) var current: Item?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, systemImage: String? = nil, duration: TimeInterval = 2.2) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            current = Item(message: message, systemImage: systemImage)
        }
        let targetID = current?.id
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self?.current?.id == targetID else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self?.current = nil
            }
        }
    }
}

struct ToastOverlayView: View {
    @Bindable var center: ToastCenter = .shared

    var body: some View {
        if let item = center.current {
            HStack(spacing: 8) {
                if let icon = item.systemImage {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlayerTheme.accent)
                }
                Text(item.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
