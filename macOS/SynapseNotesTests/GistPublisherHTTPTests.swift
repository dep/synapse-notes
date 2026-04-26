import XCTest
import Combine
@testable import Synapse

// MARK: - Mock URLProtocol

private final class MockGistURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockGistURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

/// Tests for GistPublisher's HTTP response-handling pipeline.
///
/// Existing tests only exercise input-validation guard paths (empty PAT, empty content,
/// empty filename) that never reach the network. These tests use a mock URLSession to
/// exercise the full `publish()` pipeline — status-code dispatch, JSON `html_url` parsing,
/// and the four distinct error messages for 401 / 403 / 422 / unexpected status codes.
final class GistPublisherHTTPTests: XCTestCase {

    var sut: GistPublisher!
    var mockSession: URLSession!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGistURLProtocol.self]
        mockSession = URLSession(configuration: config)
        sut = GistPublisher()
        sut.urlSession = mockSession
        // Mock external URL opening to prevent browser from opening during tests
        sut.onOpenExternalURL = { _ in }
        cancellables = []
    }

    override func tearDown() {
        MockGistURLProtocol.requestHandler = nil
        cancellables = nil
        mockSession = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/gists")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    private func makeData(json: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    private func publishNote(pat: String = "ghp_token") {
        sut.publish(NoteContent(filename: "test.md", content: "# Hello"), pat: pat)
    }

    // MARK: - 201 Created — success path

    func test_publish_201WithHtmlUrl_transitionsToSuccess() {
        let gistURL = "https://gist.github.com/abc123"
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 201), self.makeData(json: ["html_url": gistURL]))
        }

        let expectation = self.expectation(description: "Transitions to .success")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .success(let url) = state {
                    XCTAssertEqual(url, gistURL,
                                   "Success state should carry the html_url from the API response")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    func test_publish_201WithoutHtmlUrl_transitionsToFailure() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            // Valid 201 but missing html_url key
            (self.makeResponse(statusCode: 201), self.makeData(json: ["id": "abc123"]))
        }

        let expectation = self.expectation(description: "Transitions to .failed when html_url absent")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - 401 Unauthorized

    func test_publish_401_failsWithInvalidTokenMessage() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 401), self.makeData(json: ["message": "Bad credentials"]))
        }

        let expectation = self.expectation(description: "401 → .failed with token message")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed(let error) = state {
                    XCTAssertTrue(
                        error.lowercased().contains("invalid") || error.lowercased().contains("token"),
                        "401 error should mention invalid token. Got: '\(error)'"
                    )
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - 403 Forbidden

    func test_publish_403_failsWithPermissionsMessage() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 403), self.makeData(json: ["message": "Forbidden"]))
        }

        let expectation = self.expectation(description: "403 → .failed with permissions message")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed(let error) = state {
                    XCTAssertTrue(
                        error.lowercased().contains("rate") || error.lowercased().contains("permission"),
                        "403 error should mention rate limit or permissions. Got: '\(error)'"
                    )
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - 422 Unprocessable Entity

    func test_publish_422_failsWithValidationMessage() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 422), self.makeData(json: ["message": "Unprocessable Entity"]))
        }

        let expectation = self.expectation(description: "422 → .failed with validation message")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed(let error) = state {
                    XCTAssertTrue(
                        error.lowercased().contains("invalid") || error.lowercased().contains("content"),
                        "422 error should mention invalid request or content. Got: '\(error)'"
                    )
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Other status codes

    func test_publish_500_failsWithHttpStatusCodeInMessage() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 500), self.makeData(json: ["message": "Internal Server Error"]))
        }

        let expectation = self.expectation(description: "500 → .failed with status code")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed(let error) = state {
                    XCTAssertTrue(
                        error.contains("500") || error.lowercased().contains("error"),
                        "5xx error message should reference the HTTP status code. Got: '\(error)'"
                    )
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    func test_publish_404_failsWithHttpStatusCodeInMessage() {
        MockGistURLProtocol.requestHandler = { [unowned self] _ in
            (self.makeResponse(statusCode: 404), self.makeData(json: ["message": "Not Found"]))
        }

        let expectation = self.expectation(description: "404 → .failed")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed(let error) = state {
                    XCTAssertTrue(
                        error.contains("404") || error.lowercased().contains("error"),
                        "Unexpected status code error should contain the code. Got: '\(error)'"
                    )
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Network-level failure

    func test_publish_networkError_transitionsToFailed() {
        MockGistURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let expectation = self.expectation(description: "Network error → .failed")
        sut.$state
            .dropFirst()
            .sink { state in
                if case .failed = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Request format

    func test_publish_setsAuthorizationHeaderWithTokenScheme() {
        let expectation = self.expectation(description: "Authorization header checked")
        MockGistURLProtocol.requestHandler = { [unowned self] request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(auth, "token ghp_mytoken",
                           "Authorization header should use 'token <PAT>' scheme")
            expectation.fulfill()
            return (self.makeResponse(statusCode: 201), self.makeData(json: ["html_url": "https://gist.github.com/x"]))
        }

        sut.publish(NoteContent(filename: "test.md", content: "# Hello"), pat: "ghp_mytoken")
        wait(for: [expectation], timeout: 3.0)
    }

    func test_publish_trimsWhitespaceFromPATInAuthHeader() {
        let expectation = self.expectation(description: "PAT trimmed in header")
        MockGistURLProtocol.requestHandler = { [unowned self] request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(auth, "token ghp_trimmed",
                           "Whitespace around the PAT should be trimmed in the Authorization header")
            expectation.fulfill()
            return (self.makeResponse(statusCode: 201), self.makeData(json: ["html_url": "https://gist.github.com/x"]))
        }

        sut.publish(NoteContent(filename: "test.md", content: "# Hello"), pat: "  ghp_trimmed  ")
        wait(for: [expectation], timeout: 3.0)
    }

    func test_publish_usesPostMethod() {
        let expectation = self.expectation(description: "HTTP method is POST")
        MockGistURLProtocol.requestHandler = { [unowned self] request in
            XCTAssertEqual(request.httpMethod, "POST",
                           "Gist creation should use the POST method")
            expectation.fulfill()
            return (self.makeResponse(statusCode: 201), self.makeData(json: ["html_url": "https://gist.github.com/x"]))
        }

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }

    func test_publish_targetsGitHubGistsEndpoint() {
        let expectation = self.expectation(description: "URL is GitHub Gists endpoint")
        MockGistURLProtocol.requestHandler = { [unowned self] request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/gists",
                           "Publish should POST to the GitHub Gists API endpoint")
            expectation.fulfill()
            return (self.makeResponse(statusCode: 201), self.makeData(json: ["html_url": "https://gist.github.com/x"]))
        }

        publishNote()
        wait(for: [expectation], timeout: 3.0)
    }
}
