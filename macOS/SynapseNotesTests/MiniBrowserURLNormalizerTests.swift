import XCTest
@testable import Synapse

/// Tests URL normalization for the in-app browser address bar.
final class MiniBrowserURLNormalizerTests: XCTestCase {

    func test_empty_returnsNil() {
        XCTAssertNil(MiniBrowserURLNormalizer.normalizedURLString(from: ""))
        XCTAssertNil(MiniBrowserURLNormalizer.normalizedURLString(from: "   \n\t "))
    }

    func test_bareHost_prependsHttps() {
        XCTAssertEqual(
            MiniBrowserURLNormalizer.normalizedURLString(from: "example.com"),
            "https://example.com"
        )
    }

    func test_https_preserved() {
        XCTAssertEqual(
            MiniBrowserURLNormalizer.normalizedURLString(from: "https://dep.github.io/synapse"),
            "https://dep.github.io/synapse"
        )
    }

    func test_http_preserved() {
        XCTAssertEqual(
            MiniBrowserURLNormalizer.normalizedURLString(from: "http://localhost:8080"),
            "http://localhost:8080"
        )
    }

    func test_whitespaceTrimmed() {
        XCTAssertEqual(
            MiniBrowserURLNormalizer.normalizedURLString(from: "  dep.dev  "),
            "https://dep.dev"
        )
    }
}
