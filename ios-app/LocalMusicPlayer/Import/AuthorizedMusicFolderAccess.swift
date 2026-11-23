import Foundation

/// Stores the security-scoped permission granted by the Files picker for a
/// music folder. iOS does not provide a permission switch for all Files data;
/// a bookmark is the supported way to keep the user's explicit folder choice.
enum AuthorizedMusicFolderAccess {
    private static let bookmarkKey = "authorizedMusicFolder.bookmark"

    static func save(_ url: URL, defaults: UserDefaults = .standard) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmark = try url.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    static func resolve(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withoutUI],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [],
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil) {
            defaults.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }
}
