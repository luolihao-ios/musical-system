import Foundation

public struct UnsafePathError: Error, Equatable { public let path: String }

public struct SafeRelativePath: Equatable, Sendable {
    public let value: String
    private static let reserved = Set(["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })

    public init(_ path: String) throws {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.hasPrefix("\\"),
              !normalized.contains(":"),
              !parts.isEmpty,
              parts.allSatisfy(Self.isSafeSegment) else { throw UnsafePathError(path: path) }
        value = parts.joined(separator: "/")
    }

    public func resolved(below root: URL) throws -> URL {
        let standardRoot = root.standardizedFileURL
        let candidate = standardRoot.appending(path: value).standardizedFileURL
        let rootPath = standardRoot.path.hasSuffix("/") ? String(standardRoot.path.dropLast()) : standardRoot.path
        guard candidate.path.hasPrefix(rootPath + "/") else {
            throw UnsafePathError(path: value)
        }
        return candidate
    }

    private static func isSafeSegment(_ segment: String) -> Bool {
        guard segment != ".", segment != "..", !segment.hasSuffix(" "), !segment.hasSuffix("."),
              segment.rangeOfCharacter(from: CharacterSet(charactersIn: "<>\"|?*\0")) == nil else { return false }
        return !reserved.contains((segment as NSString).deletingPathExtension.uppercased())
    }
}
