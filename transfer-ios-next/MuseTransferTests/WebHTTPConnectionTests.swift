import XCTest
import Network
@testable import AiyueTransfer

final class WebHTTPConnectionTests: XCTestCase {
    func testStreamsBodyAndDownloadWithoutLoadingWholeFile() async throws {
        let queue = DispatchQueue(label: "web-test")
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        var clients: [WebHTTPConnection] = []
        listener.newConnectionHandler = { socket in
            let client = WebHTTPConnection(socket, queue: queue)
            clients.append(client)
            client.authorize = { _ in true }
            client.handle = { _, temporary, connection in connection.download(temporary) }
            client.start()
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port.rawValue)/upload")!)
        request.httpMethod = "PUT"
        let body = Data(repeating: 0x5a, count: 2 * 1024 * 1024 + 7)
        request.httpBody = body
        let (received, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(received, body)
        _ = clients
    }
}
