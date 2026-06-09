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

    func test_emptyPrompt_returnsEmptyResult() {
        let r = makeResolver(["Foo": "x"])
        let result = r.resolve(prompt: "")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    func test_trailingPunctuation_doesNotBreakMatch() {
        let r = makeResolver(["Budget": "budget body"])
        // "@Budget." at a sentence end must still resolve to "Budget".
        let result = r.resolve(prompt: "see @Budget.")
        XCTAssertEqual(result.blocks.map(\.name), ["Budget"])
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_emailAddress_isNotTreatedAsAtToken() {
        let r = makeResolver(["Bar": "bar body"])
        // "foo@bar.com" is an email — the @ is preceded by a word char, so no token.
        let result = r.resolve(prompt: "reply to foo@bar.com please")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_exactCapBoundary_keepsFirstBlockOnly() {
        let exact = String(repeating: "a", count: 100_000)
        let r = makeResolver(["One": exact, "Two": "more"], cap: 100_000)
        let result = r.resolve(prompt: "@One @Two")
        XCTAssertEqual(result.blocks.map(\.name), ["One"])
        // The whole first block fits exactly; the second is dropped by the cap.
        XCTAssertEqual(result.blocks[0].body.count, 100_000)
    }

    func test_bracketedToken_withSpaces_resolves() {
        let r = makeResolver(["My Note": "spaced body"])
        let result = r.resolve(prompt: "see @[My Note] please")
        XCTAssertEqual(result.blocks.map(\.name), ["My Note"])
        XCTAssertEqual(result.blocks[0].body, "spaced body")
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_bracketedToken_caseInsensitive() {
        let r = makeResolver(["Weekly Review": "x"])
        let result = r.resolve(prompt: "@[weekly review]")
        XCTAssertEqual(result.blocks.map(\.name), ["Weekly Review"])
    }

    func test_bareToken_stillWorksAlongsideBracket() {
        let r = makeResolver(["Foo": "f", "My Note": "m"])
        let result = r.resolve(prompt: "@Foo and @[My Note]")
        XCTAssertEqual(Set(result.blocks.map(\.name)), Set(["Foo", "My Note"]))
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_bracketedMissing_isReported() {
        let r = makeResolver(["Foo": "f"])
        let result = r.resolve(prompt: "@[No Such Note]")
        XCTAssertEqual(result.missing, ["No Such Note"])
        XCTAssertTrue(result.blocks.isEmpty)
    }
}
