import Foundation
import SwiftUI

struct MiniPlayerVisibility: Sendable {
    private(set) var isVisible = true

    mutating func dismiss() { isVisible = false }
    mutating func show() { isVisible = true }
}

private struct ShowMiniPlayerActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var showMiniPlayer: () -> Void {
        get { self[ShowMiniPlayerActionKey.self] }
        set { self[ShowMiniPlayerActionKey.self] = newValue }
    }
}
