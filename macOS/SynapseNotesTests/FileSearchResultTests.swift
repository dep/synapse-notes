import XCTest
@testable import Synapse

/// Tests the all-files search result row model (used by command palette / search UI).
final class FileSearchResultTests: XCTestCase {

    func test_identifiable_idsAreUniquePerInstance() {
        let a = FileSearchResult(
            url: URL(fileURLWithPath: "/tmp/a.md"),
            snippet: "one",
            lineNumber: 1
        )
        let b = FileSearchResult(
            url: URL(fileURLWithPath: "/tmp/b.md"),
            snippet: "two",
            lineNumber: 2
        )
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_storesFields() {
        let url = URL(fileURLWithPath: "/vault/notes/x.md")
        let row = FileSearchResult(url: url, snippet: "…match…", lineNumber: 42)
        XCTAssertEqual(row.url, url)
        XCTAssertEqual(row.snippet, "…match…")
        XCTAssertEqual(row.lineNumber, 42)
    }
}
