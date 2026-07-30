import Foundation

struct ImportedFile: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case audio
        case lyrics
    }

    let sourceURL: URL
    let kind: Kind
}

struct ImportedMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkData: Data?
}

protocol ImportedMetadataReading: Sendable {
    func read(_ url: URL) async throws -> ImportedMetadata
}
