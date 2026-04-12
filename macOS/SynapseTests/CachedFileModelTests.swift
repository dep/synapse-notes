import XCTest
@testable import Synapse

/// Tests for `CachedFile` — the vault scan snapshot stored in `noteContentCache`.
/// Wrong field semantics break graph, tags, and search without obvious UI errors.
final class CachedFileModelTests: XCTestCase {

    func test_cachedFile_storesAllFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sut = CachedFile(
            content: "body",
            modificationDate: date,
            wikiLinks: ["alpha", "beta"],
            tags: ["work", "idea"]
        )

        XCTAssertEqual(sut.content, "body")
        XCTAssertEqual(sut.modificationDate, date)
        XCTAssertEqual(sut.wikiLinks, ["alpha", "beta"])
        XCTAssertEqual(sut.tags, ["work", "idea"])
    }

    func test_cachedFile_memberwiseEquality() {
        let d = Date()
        let a = CachedFile(content: "x", modificationDate: d, wikiLinks: ["a"], tags: ["t"])
        let b = CachedFile(content: "x", modificationDate: d, wikiLinks: ["a"], tags: ["t"])
        let c = CachedFile(content: "y", modificationDate: d, wikiLinks: ["a"], tags: ["t"])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_cachedFile_emptyCollectionsAreValid() {
        let sut = CachedFile(content: "", modificationDate: nil, wikiLinks: [], tags: [])

        XCTAssertTrue(sut.wikiLinks.isEmpty)
        XCTAssertTrue(sut.tags.isEmpty)
        XCTAssertNil(sut.modificationDate)
    }
}
