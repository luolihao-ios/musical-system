import Foundation

struct AppStoreUpdate: Sendable, Equatable {
    let storeVersion: String
    let storeURL: URL?

    static func isNewer(storeVersion: String, than currentVersion: String) -> Bool {
        let store = parse(storeVersion)
        let current = parse(currentVersion)
        guard let store, let current else { return false }
        return current.lexicographicallyPrecedes(store)
    }

    static func lookup(bundleIdentifier: String, session: URLSession = .shared) async -> AppStoreUpdate? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier), URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US")]
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let app = result.results.first else { return nil }
            return AppStoreUpdate(storeVersion: app.version, storeURL: app.trackViewURL.flatMap(URL.init(string:)))
        } catch {
            return nil
        }
    }

    private static func parse(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.map { Int($0)! } + Array(repeating: 0, count: max(0, 3 - parts.count))
    }

    private struct LookupResponse: Decodable { let results: [App] }
    private struct App: Decodable { let version: String; let trackViewURL: String? }
}
