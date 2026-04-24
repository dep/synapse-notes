import XCTest
@testable import Synapse

/// Tests for `GitService.getAllFileDates()` — the batch git-log walker that backs the
/// Daily Note page's Created/Updated sections. These tests set up a real git repo with
/// commits whose author/committer dates are overridden via env vars, then assert the
/// function's output matches expectations.
final class GitServiceFileDatesTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard GitService.findGit() != nil else { return }
        initRepo()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func initRepo() {
        runGit(["init"])
        runGit(["config", "user.email", "test@example.com"])
        runGit(["config", "user.name", "Test"])
        runGit(["config", "commit.gpgsign", "false"])
    }

    @discardableResult
    private func runGit(_ args: [String], env: [String: String] = [:]) -> String {
        guard let gitPath = GitService.findGit() else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = tempDir
        var combined = ProcessInfo.processInfo.environment
        for (k, v) in env { combined[k] = v }
        p.environment = combined
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try? p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Writes `content` to `relativePath` and commits it with the given ISO 8601 date applied
    /// to both author and committer timestamps (so `%aI` and `%cI` both return it).
    private func commitFile(_ relativePath: String, content: String, on isoDate: String) {
        let fileURL = tempDir.appendingPathComponent(relativePath)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)
        runGit(["add", relativePath])
        runGit(
            ["commit", "-m", "touch \(relativePath) @ \(isoDate)"],
            env: [
                "GIT_AUTHOR_DATE": isoDate,
                "GIT_COMMITTER_DATE": isoDate,
            ]
        )
    }

    private func makeService() throws -> GitService {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        do {
            return try GitService(repoURL: tempDir)
        } catch GitError.notARepo {
            throw XCTSkip("git repo was not initialised (git init may have failed)")
        }
    }

    // MARK: - Tests

    func test_getAllFileDates_emptyRepoReturnsEmpty() throws {
        let service = try makeService()

        let dates = service.getAllFileDates()

        XCTAssertTrue(dates.isEmpty)
    }

    func test_getAllFileDates_singleCommitUsesThatDate() throws {
        commitFile("note.md", content: "hello", on: "2026-04-23T10:00:00-04:00")

        let service = try makeService()
        let dates = service.getAllFileDates()

        let entry = try XCTUnwrap(dates["note.md"])
        let expected = ISO8601DateFormatter().date(from: "2026-04-23T10:00:00-04:00")
        XCTAssertEqual(entry.created, expected)
        XCTAssertEqual(entry.updated, expected)
    }

    func test_getAllFileDates_multipleCommitsGivesOldestCreatedAndNewestUpdated() throws {
        // Three edits to the same file across different days. Content must vary so git
        // actually creates three distinct commits (no-op commits are rejected by default).
        commitFile("journal.md", content: "v1", on: "2026-04-20T09:00:00-04:00")
        commitFile("journal.md", content: "v2", on: "2026-04-22T12:00:00-04:00")
        commitFile("journal.md", content: "v3", on: "2026-04-24T15:30:00-04:00")

        let service = try makeService()
        let dates = service.getAllFileDates()

        let entry = try XCTUnwrap(dates["journal.md"])
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(entry.created, formatter.date(from: "2026-04-20T09:00:00-04:00"))
        XCTAssertEqual(entry.updated, formatter.date(from: "2026-04-24T15:30:00-04:00"))
    }

    func test_getAllFileDates_returnsIndependentEntriesForEachFile() throws {
        commitFile("a.md", content: "a", on: "2026-04-20T09:00:00-04:00")
        commitFile("b.md", content: "b", on: "2026-04-22T09:00:00-04:00")
        commitFile("c.md", content: "c", on: "2026-04-24T09:00:00-04:00")

        let service = try makeService()
        let dates = service.getAllFileDates()

        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(dates["a.md"]?.created, formatter.date(from: "2026-04-20T09:00:00-04:00"))
        XCTAssertEqual(dates["b.md"]?.created, formatter.date(from: "2026-04-22T09:00:00-04:00"))
        XCTAssertEqual(dates["c.md"]?.created, formatter.date(from: "2026-04-24T09:00:00-04:00"))
    }

    func test_getAllFileDates_handlesNestedPaths() throws {
        commitFile("Web Captures/article.md", content: "x", on: "2026-04-23T10:00:00-04:00")

        let service = try makeService()
        let dates = service.getAllFileDates()

        XCTAssertNotNil(dates["Web Captures/article.md"])
    }

    /// A regression guard for the bug that motivated this work: a vault cloned today
    /// should report a file's *author* date (actual history), not its local filesystem
    /// `creationDate` (the clone time).
    func test_getAllFileDates_reflectsAuthorDateNotFilesystemDate() throws {
        // Commit with a date a week in the past.
        commitFile("old.md", content: "old", on: "2026-04-17T08:00:00-04:00")

        // Touch the on-disk mtime/ctime to "now" so filesystem attrs disagree with git.
        let fileURL = tempDir.appendingPathComponent("old.md")
        let now = Date()
        try! FileManager.default.setAttributes(
            [.creationDate: now, .modificationDate: now],
            ofItemAtPath: fileURL.path
        )

        let service = try makeService()
        let dates = service.getAllFileDates()

        let entry = try XCTUnwrap(dates["old.md"])
        let expected = ISO8601DateFormatter().date(from: "2026-04-17T08:00:00-04:00")
        XCTAssertEqual(entry.created, expected,
            "Git author date should win over filesystem creationDate")
    }
}
