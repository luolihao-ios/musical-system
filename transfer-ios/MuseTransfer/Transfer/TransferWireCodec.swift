import Foundation

public enum TransferWireError: Error, Equatable {
    case incompleteMessage
    case headersTooLarge
    case bodyTooLarge
    case malformedRequest
    case invalidContentLength
    case invalidEnvelope
    case invalidEndpoint
}

public struct TransferHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public static func parse(_ data: Data, maximumHeaderBytes: Int, maximumBodyBytes: Int) throws -> Self {
        let separator = Data("\r\n\r\n".utf8)
        guard let boundary = data.range(of: separator) else {
            if data.count > maximumHeaderBytes { throw TransferWireError.headersTooLarge }
            throw TransferWireError.incompleteMessage
        }
        guard boundary.lowerBound <= maximumHeaderBytes else { throw TransferWireError.headersTooLarge }
        guard let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { throw TransferWireError.malformedRequest }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1" else { throw TransferWireError.malformedRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw TransferWireError.malformedRequest }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let lengthText = headers["content-length"], let length = Int(lengthText), length >= 0 else { throw TransferWireError.invalidContentLength }
        guard length <= maximumBodyBytes else { throw TransferWireError.bodyTooLarge }
        let bodyStart = boundary.upperBound
        guard data.count >= bodyStart + length else { throw TransferWireError.incompleteMessage }
        return Self(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                    body: Data(data[bodyStart ..< bodyStart + length]))
    }
}

public enum TransferEnvelopeCodec {
    public static func pack(_ envelope: TransferEncryptedEnvelope) throws -> Data {
        guard envelope.nonce.count == 12, envelope.tag.count == 16 else { throw TransferWireError.invalidEnvelope }
        return envelope.nonce + envelope.tag + envelope.ciphertext
    }

    public static func unpack(_ data: Data) throws -> TransferEncryptedEnvelope {
        guard data.count >= 28 else { throw TransferWireError.invalidEnvelope }
        return TransferEncryptedEnvelope(nonce: Data(data.prefix(12)), ciphertext: Data(data.dropFirst(28)), tag: Data(data.dropFirst(12).prefix(16)))
    }
}

public struct TransferEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, port > 0 else { throw TransferWireError.invalidEndpoint }
        self.host = host; self.port = port
    }

    public init(manualAddress: String) throws {
        guard let colon = manualAddress.lastIndex(of: ":"), colon != manualAddress.startIndex,
              let value = Int(manualAddress[manualAddress.index(after: colon)...]), (1...65_535).contains(value) else {
            throw TransferWireError.invalidEndpoint
        }
        try self.init(host: String(manualAddress[..<colon]), port: UInt16(value))
    }
}
