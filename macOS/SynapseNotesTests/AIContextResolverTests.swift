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

    // MARK: Folder resolution

    /// Builds a resolver where files live at explicit paths and folders are provided.
    private func makeFolderResolver(
        files: [String: String],   // absolute path -> body
        folders: [String]          // absolute folder paths
    ) -> AIContextResolver {
        let fileURLs = files.keys.map { URL(fileURLWithPath: $0) }
        let folderURLs = folders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return AIContextResolver(
            allFiles: fileURLs,
            allFolders: folderURLs,
            readContents: { url in files[url.path] }
        )
    }

    func test_folderToken_concatenatesDirectChildren() {
        let r = makeFolderResolver(
            files: [
                "/vault/Weekly Summaries/Mon.md": "monday",
                "/vault/Weekly Summaries/Tue.md": "tuesday",
                "/vault/Other/Skip.md": "nope"
            ],
            folders: ["/vault/Weekly Summaries", "/vault/Other"]
        )
        let result = r.resolve(prompt: "summarize @[Weekly Summaries]")
        XCTAssertEqual(result.blocks.map(\.name), ["Weekly Summaries"])
        let body = result.blocks[0].body
        XCTAssertTrue(body.contains("monday"))
        XCTAssertTrue(body.contains("tuesday"))
        XCTAssertFalse(body.contains("nope"))   // not a child of this folder
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_folderToken_caseInsensitive() {
        let r = makeFolderResolver(
            files: ["/vault/Weekly Summaries/A.md": "alpha"],
            folders: ["/vault/Weekly Summaries"]
        )
        let result = r.resolve(prompt: "@[weekly summaries]")
        XCTAssertEqual(result.blocks.map(\.name), ["Weekly Summaries"])
        XCTAssertTrue(result.blocks[0].body.contains("alpha"))
    }

    func test_emptyFolder_isReportedMissing() {
        let r = makeFolderResolver(
            files: [:],
            folders: ["/vault/Empty"]
        )
        let result = r.resolve(prompt: "@Empty")
        XCTAssertEqual(result.missing, ["Empty"])
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func test_fileWins_overFolderOfSameName() {
        let r = makeFolderResolver(
            files: [
                "/vault/Notes.md": "the file",
                "/vault/Notes/child.md": "the folder child"
            ],
            folders: ["/vault/Notes"]
        )
        let result = r.resolve(prompt: "@Notes")
        XCTAssertEqual(result.blocks.map(\.name), ["Notes"])
        XCTAssertEqual(result.blocks[0].body, "the file")   // file preferred
    }
}
