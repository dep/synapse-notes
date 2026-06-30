import XCTest
@testable import Synapse

private final class MockSSEURLProtocol: URLProtocol {
    static var responseStatus: Int = 200
    static var bodyData: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: MockSSEURLProtocol.responseStatus,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockSSEURLProtocol.bodyData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class MockNonHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // A plain URLResponse (not HTTPURLResponse) triggers .badResponse.
        let response = URLResponse(url: request.url!, mimeType: "text/plain",
                                   expectedContentLength: 0, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AnthropicClientTests: XCTestCase {
    private func makeClient() -> AnthropicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        return AnthropicClient(apiKey: "sk-test", urlSession: URLSession(configuration: config))
    }

    private func sse(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").appending("\n").utf8)
    }

    override func tearDown() {
        MockSSEURLProtocol.responseStatus = 200
        MockSSEURLProtocol.bodyData = Data()
        super.tearDown()
    }

    func test_streamsTextDeltasInOrder() async throws {
        MockSSEURLProtocol.responseStatus = 200
        MockSSEURLProtocol.bodyData = sse([
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":", world"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let client = makeClient()
        var collected = ""
        for try await delta in client.stream(body: ["model": "claude-sonnet-5"]) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello, world")
    }

    func test_ignoresNonDeltaEvents() async throws {
        MockSSEURLProtocol.bodyData = sse([
            #"data: {"type":"message_start","message":{}}"#,
            #"data: {"type":"content_block_start","index":0}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"X"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let client = makeClient()
        var collected = ""
        for try await delta in client.stream(body: [:]) { collected += delta }
        XCTAssertEqual(collected, "X")
    }

    func test_401_throwsInvalidKey() async {
        MockSSEURLProtocol.responseStatus = 401
        MockSSEURLProtocol.bodyData = Data()
        let client = makeClient()
        do {
            for try await _ in client.stream(body: [:]) {}
            XCTFail("expected throw")
        } catch let error as AnthropicClient.ClientError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_500_throwsServerError() async {
        MockSSEURLProtocol.responseStatus = 500
        let client = makeClient()
        do {
            for try await _ in client.stream(body: [:]) {}
            XCTFail("expected throw")
        } catch let error as AnthropicClient.ClientError {
            XCTAssertEqual(error, .server(status: 500))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_nonHTTPResponse_throwsBadResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNonHTTPURLProtocol.self]
        let client = AnthropicClient(apiKey: "sk-test", urlSession: URLSession(configuration: config))
        do {
            for try await _ in client.stream(body: [:]) {}
            XCTFail("expected throw")
        } catch let error as AnthropicClient.ClientError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_nonJSONDataLine_isIgnored() async throws {
        MockSSEURLProtocol.responseStatus = 200
        MockSSEURLProtocol.bodyData = sse([
            "data: [DONE]",
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Y"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let client = makeClient()
        var collected = ""
        for try await delta in client.stream(body: [:]) { collected += delta }
        XCTAssertEqual(collected, "Y")
    }
}
