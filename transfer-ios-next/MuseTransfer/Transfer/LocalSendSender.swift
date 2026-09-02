import Foundation

public enum LocalSendSenderError: Error { case invalidResponse, rejected }

public final class LocalSendSender: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(files urls: [URL], to endpoint: URL, local: DeviceInfo) async throws {
        let metadata = try urls.reduce(into: [String: FileMetadata]()) { result, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let id = UUID().uuidString.lowercased()
            result[id] = FileMetadata(id: id, fileName: url.lastPathComponent, size: Int64(values.fileSize ?? 0), fileType: values.contentType?.preferredMIMEType ?? "application/octet-stream")
        }
        var prepare = URLRequest(url: endpoint.appending(path: "/api/localsend/v2/prepare-upload"))
        prepare.httpMethod = "POST"; prepare.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prepare.httpBody = try JSONEncoder().encode(PrepareUploadRequest(info: local, files: metadata))
        let (data, response) = try await session.data(for: prepare)
        guard let http = response as? HTTPURLResponse else { throw LocalSendSenderError.invalidResponse }
        guard http.statusCode != 403 else { throw LocalSendSenderError.rejected }
        guard (200..<300).contains(http.statusCode) else { throw LocalSendSenderError.invalidResponse }
        let accepted = try JSONDecoder().decode(PrepareUploadResponse.self, from: data)
        for (id, file) in metadata {
            guard let token = accepted.files[id] else { throw LocalSendSenderError.invalidResponse }
            var components = URLComponents(url: endpoint.appending(path: "/api/localsend/v2/upload"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "sessionId", value: accepted.sessionId), URLQueryItem(name: "fileId", value: id), URLQueryItem(name: "token", value: token)]
            var upload = URLRequest(url: components.url!); upload.httpMethod = "POST"; upload.httpBody = try Data(contentsOf: urls.first { $0.lastPathComponent == file.fileName }!)
            let (_, uploadResponse) = try await session.data(for: upload)
            guard let result = uploadResponse as? HTTPURLResponse, (200..<300).contains(result.statusCode) else { throw LocalSendSenderError.invalidResponse }
        }
    }
}
