import Foundation
import SwiftUI

struct MiniPlayerVisibility: Sendable {
    private(set) var isVisible = true

    mutating func dismiss() { isVisible = false }
    mutating func show() { isVisible = true }
}

@MainActor
private struct ShowMiniPlayerActionKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var showMiniPlayer: @MainActor () -> Void {
        get { self[ShowMiniPlayerActionKey.self] }
        set { self[ShowMiniPlayerActionKey.self] = newValue }
    }
}
