import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
