import XCTest
import Combine
@testable import Synapse

// MARK: - Mock URLProtocol

private final class MockAutoUpdaterURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockAutoUpdaterURLProtocol.requestHandler else {
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

/// Tests for AutoUpdater.checkForUpdates() integration path.
///
/// Existing AutoUpdaterTests cover `isNewerVersion()` in isolation and the initial
/// published state. These tests exercise the full `checkForUpdatesOnLaunch()` pipeline:
/// constructing the correct GitHub API URL, setting the required Accept header,
/// decoding the release response, stripping the 'v' version prefix, and toggling
/// `updateAvailable` and `latestVersion` correctly for newer / older / absent versions.
@MainActor
final class AutoUpdaterFetchTests: XCTestCase {

    var updater: AutoUpdater!
    var mockSession: URLSession!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAutoUpdaterURLProtocol.self]
        mockSession = URLSession(configuration: config)
        updater = AutoUpdater()
        updater.urlSession = mockSession
        cancellables = []
    }

    override func tearDown() async throws {
        MockAutoUpdaterURLProtocol.requestHandler = nil
        cancellables = nil
        updater = nil
        mockSession = nil
    }

    // MARK: - Helpers

    private func makeReleaseData(tagName: String) -> Data {
        let json: [String: Any] = [
            "tag_name": tagName,
            "name": "Release \(tagName)",
            "assets": []
        ]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    private func makeResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.github.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    // MARK: - API URL correctness

    func test_checkForUpdatesOnLaunch_callsGitHubReleasesLatestEndpoint() async {
        let expectation = XCTestExpectation(description: "Correct URL called")
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("api.github.com"),
                          "Should call GitHub API. Got: \(urlString)")
            XCTAssertTrue(urlString.contains("dep/synapse"),
                          "Should target dep/synapse repo. Got: \(urlString)")
            XCTAssertTrue(urlString.contains("releases/latest"),
                          "Should target the latest release endpoint. Got: \(urlString)")
            expectation.fulfill()
            return (self.makeResponse(for: request, statusCode: 404), Data())
        }

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    func test_checkForUpdatesOnLaunch_setsGitHubV3AcceptHeader() async {
        let expectation = XCTestExpectation(description: "Accept header set correctly")
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            let accept = request.value(forHTTPHeaderField: "Accept")
            XCTAssertEqual(accept, "application/vnd.github+json",
                           "Should set the GitHub API v3 Accept header")
            expectation.fulfill()
            return (self.makeResponse(for: request, statusCode: 404), Data())
        }

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)
    }

    // MARK: - Newer version detected

    func test_checkForUpdatesOnLaunch_newerVersion_setsUpdateAvailableTrue() async {
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            (self.makeResponse(for: request, statusCode: 200), self.makeReleaseData(tagName: "v99.0.0"))
        }

        let expectation = XCTestExpectation(description: "updateAvailable becomes true")
        cancellables.insert(
            updater.$updateAvailable.sink { available in
                if available { expectation.fulfill() }
            }
        )

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertTrue(updater.updateAvailable,
                      "updateAvailable should be true when remote version is newer")
    }

    func test_checkForUpdatesOnLaunch_newerVersion_setsLatestVersionWithoutVPrefix() async {
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            (self.makeResponse(for: request, statusCode: 200), self.makeReleaseData(tagName: "v99.1.2"))
        }

        let expectation = XCTestExpectation(description: "latestVersion set")
        cancellables.insert(
            updater.$latestVersion.sink { version in
                if version != nil { expectation.fulfill() }
            }
        )

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(updater.latestVersion, "99.1.2",
                       "The 'v' prefix in the tag name should be stripped when storing latestVersion")
    }

    func test_checkForUpdatesOnLaunch_tagWithoutVPrefix_parsedCorrectly() async {
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            (self.makeResponse(for: request, statusCode: 200), self.makeReleaseData(tagName: "99.0.0"))
        }

        let expectation = XCTestExpectation(description: "latestVersion set for un-prefixed tag")
        cancellables.insert(
            updater.$latestVersion.sink { version in
                if version != nil { expectation.fulfill() }
            }
        )

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(updater.latestVersion, "99.0.0",
                       "A tag without a 'v' prefix should be stored as-is")
    }

    // MARK: - No update needed

    func test_checkForUpdatesOnLaunch_olderVersion_updateAvailableRemainesFalse() async {
        // v0.0.1 is always older than any real current build
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            (self.makeResponse(for: request, statusCode: 200), self.makeReleaseData(tagName: "v0.0.1"))
        }

        let expectation = XCTestExpectation(description: "latestVersion populated")
        cancellables.insert(
            updater.$latestVersion.sink { version in
                if version != nil { expectation.fulfill() }
            }
        )

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertFalse(updater.updateAvailable,
                       "updateAvailable should remain false when remote version is older than current")
    }

    // MARK: - Non-200 / error responses (silent fail)

    func test_checkForUpdatesOnLaunch_404Response_updateAvailableRemainsFalse() async {
        let requestHandled = XCTestExpectation(description: "Request handled")
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                requestHandled.fulfill()
            }
            return (self.makeResponse(for: request, statusCode: 404), Data())
        }

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [requestHandled], timeout: 3.0)

        // Allow the async Task inside checkForUpdatesOnLaunch to fully unwind
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(updater.updateAvailable,
                       "A 404 response should not set updateAvailable (silent fail)")
        XCTAssertNil(updater.latestVersion,
                     "A 404 response should not set latestVersion")
    }

    func test_checkForUpdatesOnLaunch_networkError_updateAvailableRemainsFalse() async {
        let requestHandled = XCTestExpectation(description: "Request attempted")
        var handlerFired = false
        MockAutoUpdaterURLProtocol.requestHandler = { [unowned self] request in
            if !handlerFired {
                handlerFired = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    requestHandled.fulfill()
                }
            }
            throw URLError(.notConnectedToInternet)
        }

        updater.checkForUpdatesOnLaunch()
        await fulfillment(of: [requestHandled], timeout: 3.0)

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(updater.updateAvailable,
                       "A network error should not set updateAvailable (silent fail)")
    }

    // MARK: - updateAvailable starts false

    func test_initialState_updateAvailableIsFalse() {
        XCTAssertFalse(updater.updateAvailable, "updateAvailable should start as false")
        XCTAssertNil(updater.latestVersion, "latestVersion should start as nil")
    }
}
