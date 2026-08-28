import Foundation

public enum MusicGrouper {
    private static let audio = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac", "ogg", "opus"])
    private static let companions = Set(["lrc", "jpg", "jpeg", "png", "webp", "m3u", "m3u8"])

    public static func group(_ items: [TransferItem]) -> [MusicGroup] {
        let grouped = Dictionary(grouping: items) { URL(fileURLWithPath: $0.relativePath).deletingLastPathComponent().path }
        return grouped.sorted { $0.key < $1.key }.compactMap { directory, entries in
            guard entries.contains(where: { audio.contains(URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased()) }) else { return nil }
            let ids = entries.filter { audio.contains(URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased()) || companions.contains(URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased()) }.map(\.id)
            guard !ids.isEmpty else { return nil }
            let digest = Data(directory.utf8).base64EncodedString().prefix(12)
            return MusicGroup(id: "music-\(digest)", itemIds: ids)
        }
    }
}
