import XCTest
@testable import Synapse

/// Tests for the cached noteIndex (6B fix) and inverted-word search index (6A).
///
/// Design:
///   - `AppState.cachedNoteIndex`  — `[String: URL]` mapping normalised title → file URL.
///     Built lazily from `allFiles` and updated incrementally when files are added/removed.
///   - `AppState.wordSearchIndex`  — `[String: Set<URL>]` mapping lowercase word → files
///     whose content contains that word. Supports substring search via prefix scanning.
///     Updated incrementally via `updateCacheIncrementally`.
///
/// SearchView uses `wordSearchIndex` to get a candidate set first, then does exact
/// substring matching only on those candidates.
final class SearchIndexTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(named: String, content: String) -> URL {
        let url = tempDir.appendingPathComponent(named)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 6B: Cached noteIndex

    func test_cachedNoteIndex_isEmptyBeforeVaultOpen() {
        XCTAssertTrue(sut.cachedNoteIndex.isEmpty)
    }

    func test_cachedNoteIndex_populatesAfterRefresh() {
        _ = makeFile(named: "Alpha.md", content: "hello")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.cachedNoteIndex.isEmpty,
                       "cachedNoteIndex should be populated after refreshAllFiles")
    }

    func test_cachedNoteIndex_mapsNormalisedTitleToURL() {
        let file = makeFile(named: "My Note.md", content: "content")
        sut.openFolder(tempDir)
        XCTAssertEqual(sut.cachedNoteIndex["my note"], file,
                       "Title should be lowercased in the index key")
    }

    func test_cachedNoteIndex_isStableOnRepeatedAccess() {
        makeFile(named: "Stable.md", content: "x")
        sut.openFolder(tempDir)
        let first = sut.cachedNoteIndex
        let second = sut.cachedNoteIndex
        XCTAssertEqual(first, second,
                       "cachedNoteIndex must return the same value on consecutive accesses")
    }

    func test_cachedNoteIndex_updatesWhenFileIsAdded() {
        makeFile(named: "First.md", content: "a")
        sut.openFolder(tempDir)
        let before = sut.cachedNoteIndex.count

        makeFile(named: "Second.md", content: "b")
        sut.refreshAllFiles()
        XCTAssertEqual(sut.cachedNoteIndex.count, before + 1,
                       "cachedNoteIndex must grow when a new file is added")
    }

    func test_cachedNoteIndex_clearsOnVaultClose() {
        makeFile(named: "Temp.md", content: "data")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.cachedNoteIndex.isEmpty)
        sut.exitVault()
        XCTAssertTrue(sut.cachedNoteIndex.isEmpty,
                      "cachedNoteIndex must clear when vault is closed")
    }

    func test_relationshipsForSelectedFile_usesO1NoteIndex() {
        // This is the regression guard: if noteIndex() still rebuilds from allFiles
        // on every call, this test will still pass — but the perf test in the issue
        // will catch it. Here we just verify correctness is maintained.
        let a = makeFile(named: "Alpha.md", content: "Links to [[Beta]]")
        let b = makeFile(named: "Beta.md", content: "nothing")
        sut.openFolder(tempDir)
        sut.openFile(a)
        let rels = sut.relationshipsForSelectedFile()
        XCTAssertEqual(rels?.outbound, [b], "Outbound link to Beta should resolve via cachedNoteIndex")
    }

    // MARK: - 6A: Word search index

    func test_wordSearchIndex_isEmptyBeforeVaultOpen() {
        XCTAssertTrue(sut.wordSearchIndex.isEmpty)
    }

    func test_wordSearchIndex_indexesWordsAfterRefresh() {
        makeFile(named: "note.md", content: "hello world")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.wordSearchIndex.isEmpty,
                       "wordSearchIndex should be populated after vault open")
    }

    func test_wordSearchIndex_mapsWordToContainingFiles() {
        let file = makeFile(named: "note.md", content: "hello world")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.wordSearchIndex["hello"]?.contains(file) == true,
                      "word 'hello' should map to the file containing it")
        XCTAssertTrue(sut.wordSearchIndex["world"]?.contains(file) == true)
    }

    func test_wordSearchIndex_isLowercase() {
        let file = makeFile(named: "note.md", content: "SWIFT Programming")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.wordSearchIndex["swift"]?.contains(file) == true,
                      "Words should be indexed in lowercase")
        XCTAssertNil(sut.wordSearchIndex["SWIFT"])
    }

    func test_wordSearchIndex_multipleFilesPerWord() {
        let a = makeFile(named: "a.md", content: "swift is great")
        let b = makeFile(named: "b.md", content: "swift language")
        sut.openFolder(tempDir)
        let files = sut.wordSearchIndex["swift"] ?? []
        XCTAssertTrue(files.contains(a))
        XCTAssertTrue(files.contains(b))
    }

    func test_wordSearchIndex_updatesIncrementallyOnFileChange() {
        let file = makeFile(named: "note.md", content: "apple banana")
        sut.openFolder(tempDir)
        XCTAssertNil(sut.wordSearchIndex["cherry"],
                     "cherry not yet in vault")

        // Update file to contain a new word
        try! "apple banana cherry".write(to: file, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [file])

        XCTAssertTrue(sut.wordSearchIndex["cherry"]?.contains(file) == true,
                      "wordSearchIndex must update incrementally when file content changes")
    }

    func test_wordSearchIndex_removesStaleWordsOnFileChange() {
        let file = makeFile(named: "note.md", content: "apple banana")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.wordSearchIndex["banana"]?.contains(file) == true)

        // Remove 'banana' from the file
        try! "apple only now".write(to: file, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [file])

        XCTAssertFalse(sut.wordSearchIndex["banana"]?.contains(file) == true,
                       "Stale word 'banana' must be removed from index when file content changes")
    }

    func test_wordSearchIndex_clearsOnVaultClose() {
        makeFile(named: "note.md", content: "hello")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.wordSearchIndex.isEmpty)
        sut.exitVault()
        XCTAssertTrue(sut.wordSearchIndex.isEmpty)
    }

    // MARK: - candidateFiles(for:) — the search pre-filter

    func test_candidateFiles_returnsFilesContainingQueryWord() {
        let file = makeFile(named: "note.md", content: "swift concurrency")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "swift")
        XCTAssertTrue(candidates.contains(file))
    }

    func test_candidateFiles_supportsSubstringQuery() {
        // "swif" is a prefix of "swift" — substring search must still find it
        let file = makeFile(named: "note.md", content: "swift is cool")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "swif")
        XCTAssertTrue(candidates.contains(file),
                      "Substring query 'swif' must return files containing 'swift'")
    }

    func test_candidateFiles_isCaseInsensitive() {
        let file = makeFile(named: "note.md", content: "Swift Language")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "SWIFT")
        XCTAssertTrue(candidates.contains(file))
    }

    func test_candidateFiles_returnsEmptyForUnknownWord() {
        makeFile(named: "note.md", content: "hello world")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "xyzzy")
        XCTAssertTrue(candidates.isEmpty)
    }

    func test_candidateFiles_multiWordQueryIntersectsResults() {
        let both = makeFile(named: "both.md", content: "apple banana cherry")
        let onlyApple = makeFile(named: "apple.md", content: "apple only")
        sut.openFolder(tempDir)
        // Multi-word query: "apple banana" — only 'both' has both words
        let candidates = sut.candidateFiles(for: "apple banana")
        XCTAssertTrue(candidates.contains(both))
        XCTAssertFalse(candidates.contains(onlyApple),
                       "Multi-word query should intersect: only files with ALL words are candidates")
    }

    // MARK: - Minimum word length fallback

    func test_candidateFiles_shortQueryFallsBackToAllFiles() {
        // 1- and 2-char queries are below the minimum; should return all files
        // rather than doing an expensive near-total prefix scan.
        let file = makeFile(named: "note.md", content: "hi there")
        sut.openFolder(tempDir)
        let candidates1 = sut.candidateFiles(for: "h")
        let candidates2 = sut.candidateFiles(for: "hi")
        XCTAssertTrue(candidates1.contains(file),
                      "1-char query must fall back to all files")
        XCTAssertTrue(candidates2.contains(file),
                      "2-char query must fall back to all files")
    }

    func test_candidateFiles_threeCharQueryUsesIndex() {
        // 3-char query meets the minimum — index should be consulted.
        let match = makeFile(named: "match.md", content: "concurrency rocks")
        let noMatch = makeFile(named: "other.md", content: "nothing relevant")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "con")
        XCTAssertTrue(candidates.contains(match),
                      "3-char prefix 'con' should match 'concurrency'")
        XCTAssertFalse(candidates.contains(noMatch),
                       "File without matching word should be excluded")
    }

    func test_searchIndexMinWordLength_isThree() {
        XCTAssertEqual(AppState.searchIndexMinWordLength, 3)
    }

    // MARK: - Unicode safety in wordTokens

    func test_wordTokens_doesNotProduceSpuriousTokensForUnicodeLengthChangingChars() {
        // Turkish dotted capital I (İ, U+0130) lowercases to "i\u{0307}" (two code units),
        // changing the string length. This used to cause the range from the lowercased
        // enumeration to be applied to the original string, producing garbage tokens.
        let text = "İstanbul meeting notes"
        let tokens = AppState.wordTokens(from: text)
        XCTAssertTrue(tokens.contains("i̇stanbul") || tokens.contains("istanbul"),
                      "Turkish I should tokenise to its lowercased form")
        XCTAssertTrue(tokens.contains("meeting"))
        XCTAssertTrue(tokens.contains("notes"))
        // Must NOT contain any spurious tokens that aren't words in the input
        let unexpected = tokens.filter { $0.contains("tacoma") || $0.count > 20 }
        XCTAssertTrue(unexpected.isEmpty, "No spurious tokens: \(unexpected)")
    }

    func test_wordTokens_fileWithSpecialCharsDoesNotPolluteCandidateIndex() {
        // Regression: a file containing Unicode length-changing chars was causing
        // unrelated files to appear as candidates for queries they don't contain.
        let unrelated = makeFile(named: "unrelated.md", content: "İstanbul notes from the meeting")
        let target = makeFile(named: "target.md", content: "tacoma washington")
        sut.openFolder(tempDir)
        let candidates = sut.candidateFiles(for: "tacoma")
        XCTAssertTrue(candidates.contains(target),
                      "File containing 'tacoma' must be a candidate")
        XCTAssertFalse(candidates.contains(unrelated),
                       "File NOT containing 'tacoma' must not be a candidate (spurious index pollution)")
    }
}


