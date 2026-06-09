import XCTest
@testable import Synapse

final class AIContextResolverTests: XCTestCase {
    // Build a resolver whose "files" are in-memory: name -> body.
    private func makeResolver(_ files: [String: String], cap: Int = 100_000) -> AIContextResolver {
        let urls = files.keys.map { URL(fileURLWithPath: "/vault/\($0).md") }
        return AIContextResolver(
            allFiles: urls,
            charCap: cap,
            readContents: { url in files[url.deletingPathExtension().lastPathComponent] }
        )
    }

    func test_noAtTokens_returnsEmptyContextNoMissing() {
        let r = makeResolver(["Foo": "body"])
        let result = r.resolve(prompt: "summarize the note")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    func test_resolvesSingleAtToken_caseInsensitive() {
        let r = makeResolver(["Daily": "daily body"])
        let result = r.resolve(prompt: "use @daily please")
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].name, "Daily")
        XCTAssertEqual(result.blocks[0].body, "daily body")
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_missingRef_isReportedAndSkipped() {
        let r = makeResolver(["Foo": "x"])
        let result = r.resolve(prompt: "@nope and @Foo")
        XCTAssertEqual(result.blocks.map(\.name), ["Foo"])
        XCTAssertEqual(result.missing, ["nope"])
    }

    func test_overCap_truncatesAndFlags() {
        let big = String(repeating: "a", count: 60_000)
        let r = makeResolver(["One": big, "Two": big], cap: 100_000)
        let result = r.resolve(prompt: "@One @Two")
        XCTAssertTrue(result.truncated)
        let total = result.blocks.reduce(0) { $0 + $1.body.count }
        XCTAssertLessThanOrEqual(total, 100_000)
    }

    func test_duplicateRefs_resolvedOnce() {
        let r = makeResolver(["Foo": "x"])
        let result = r.resolve(prompt: "@Foo and again @foo")
        XCTAssertEqual(result.blocks.count, 1)
    }
}
