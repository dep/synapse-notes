import XCTest
@testable import Synapse

/// Tests for the full-text vault search algorithm used by AllFilesSearchView.
///
/// The search logic lives inside the View (scheduleSearch), so these tests
/// exercise the same algorithm in isolation to guard against regressions in:
///  - case-insensitive matching
///  - correct 1-based line numbers
///  - correct snippet extraction
///  - the 200-result cap
///  - binary/non-UTF-8 files being skipped gracefully
final class VaultFullTextSearchTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(named name: String, content: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Runs the same algorithm as AllFilesSearchView.scheduleSearch synchronously
    /// and returns the results.
    private func search(query: String, in files: [URL], cap: Int = 200) -> [FileSearchResult] {
        let needle = query.lowercased()
        var found: [FileSearchResult] = []
        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                if line.lowercased().contains(needle) {
                    found.append(FileSearchResult(
                        url: url,
                        snippet: line.trimmingCharacters(in: .whitespaces),
                        lineNumber: idx + 1
                    ))
                    if found.count >= cap { break }
                }
            }
            if found.count >= cap { break }
        }
        return found
    }

    // MARK: - Basic matching

    func test_search_findsExactMatch() {
        let file = makeFile(named: "note.md", content: "Hello world\nSecond line")
        let results = search(query: "Hello world", in: [file])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url, file)
    }

    func test_search_isCaseInsensitive() {
        let file = makeFile(named: "note.md", content: "Swift is awesome")
        let upper = search(query: "SWIFT", in: [file])
        let lower = search(query: "swift", in: [file])
        XCTAssertEqual(upper.count, 1)
        XCTAssertEqual(lower.count, 1)
    }

    func test_search_reportsCorrectLineNumber() {
        let file = makeFile(named: "note.md", content: "line one\nline two\nline three needle here\nline four")
        let results = search(query: "needle", in: [file])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lineNumber, 3, "Needle is on line 3 (1-based)")
    }

    func test_search_firstLineIsLineNumber1() {
        let file = makeFile(named: "note.md", content: "needle is here\nsecond line")
        let results = search(query: "needle", in: [file])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lineNumber, 1)
    }

    func test_search_snippetMatchesLine() {
        let file = makeFile(named: "note.md", content: "  trimmed snippet line  ")
        let results = search(query: "snippet", in: [file])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].snippet, "trimmed snippet line",
                       "Snippet should be whitespace-trimmed")
    }

    // MARK: - Multi-file search

    func test_search_findsMatchesAcrossMultipleFiles() {
        let file1 = makeFile(named: "a.md", content: "alpha beta")
        let file2 = makeFile(named: "b.md", content: "gamma delta")
        let file3 = makeFile(named: "c.md", content: "alpha omega")
        let results = search(query: "alpha", in: [file1, file2, file3])
        XCTAssertEqual(results.count, 2)
        let matchedURLs = results.map(\.url)
        XCTAssertTrue(matchedURLs.contains(file1))
        XCTAssertTrue(matchedURLs.contains(file3))
        XCTAssertFalse(matchedURLs.contains(file2))
    }

    func test_search_returnsEmptyWhenNeedleAbsent() {
        let file = makeFile(named: "note.md", content: "Nothing relevant here")
        let results = search(query: "xyzzy", in: [file])
        XCTAssertTrue(results.isEmpty)
    }

    func test_search_returnsEmptyForEmptyFileList() {
        let results = search(query: "anything", in: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Result cap

    func test_search_respectsCap() {
        // Create one file whose content has more than `cap` matching lines.
        let lines = (1...50).map { "match on line \($0)" }.joined(separator: "\n")
        let file = makeFile(named: "big.md", content: lines)
        let results = search(query: "match", in: [file], cap: 10)
        XCTAssertEqual(results.count, 10, "Must stop at the cap")
    }

    func test_search_cap200_stopsAcrossFiles() {
        // Each file contributes many matching lines; verify the total caps at 200.
        var files: [URL] = []
        for i in 1...10 {
            let lines = (1...30).map { "needle line \($0)" }.joined(separator: "\n")
            files.append(makeFile(named: "file\(i).md", content: lines))
        }
        let results = search(query: "needle", in: files, cap: 200)
        XCTAssertEqual(results.count, 200)
    }

    // MARK: - Non-UTF-8 files

    func test_search_skipsNonUTF8Files() {
        // Write raw bytes that are not valid UTF-8.
        let badURL = tempDir.appendingPathComponent("binary.bin")
        let badData = Data([0xFF, 0xFE, 0x00, 0x01])
        try! badData.write(to: badURL)

        let goodFile = makeFile(named: "good.md", content: "needle in here")

        let results = search(query: "needle", in: [badURL, goodFile])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url, goodFile)
    }

    // MARK: - FileSearchResult model

    func test_fileSearchResult_hasUniqueIDs() {
        let url = makeFile(named: "r.md", content: "a\nb")
        let r1 = FileSearchResult(url: url, snippet: "a", lineNumber: 1)
        let r2 = FileSearchResult(url: url, snippet: "b", lineNumber: 2)
        XCTAssertNotEqual(r1.id, r2.id, "Each FileSearchResult must get a unique UUID")
    }

    func test_fileSearchResult_storesAllFields() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = FileSearchResult(url: url, snippet: "hello world", lineNumber: 42)
        XCTAssertEqual(result.url, url)
        XCTAssertEqual(result.snippet, "hello world")
        XCTAssertEqual(result.lineNumber, 42)
    }
}
