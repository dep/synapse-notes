import XCTest
@testable import Synapse

/// Tests that `AppState.notesCreatedOnDate` / `notesModifiedOnDate` prefer git commit
/// dates over filesystem timestamps when the vault is a git repo.
///
/// These are higher-level integration tests than `AppStateDateFilteringTests`: they
/// `openFolder` a real git repo so `gitService` and `gitDateCache` wire up end to end.
final class AppStateGitDateFilteringTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = AppState()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func runGit(_ args: [String], env: [String: String] = [:]) -> String {
        runGit(at: tempDir, args, env: env)
    }

    @discardableResult
    private func runGit(at directory: URL, _ args: [String], env: [String: String] = [:]) -> String {
        guard let gitPath = GitService.findGit() else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = directory
        var combined = ProcessInfo.processInfo.environment
        for (k, v) in env { combined[k] = v }
        p.environment = combined
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let data = (p.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func initRepo() throws {
        guard GitService.findGit() != nil else { throw XCTSkip("git not available") }
        runGit(["init"])
        runGit(["config", "user.email", "test@example.com"])
        runGit(["config", "user.name", "Test"])
        runGit(["config", "commit.gpgsign", "false"])
    }

    private func commitFile(_ relativePath: String, on isoDate: String) {
        let fileURL = tempDir.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Vary content per commit so git doesn't short-circuit a no-op commit when the same
        // file is written twice with identical content (the second commit would then be
        // rejected and the first commit's date would stick as both created and updated).
        try! "content @ \(isoDate)".write(to: fileURL, atomically: true, encoding: .utf8)
        runGit(["add", relativePath])
        runGit(
            ["commit", "-m", "commit \(relativePath) @ \(isoDate)"],
            env: [
                "GIT_AUTHOR_DATE": isoDate,
                "GIT_COMMITTER_DATE": isoDate,
            ]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = 0; c.second = 0
        return calendar.date(from: c)!
    }

    // MARK: - Tests

    /// The core regression: a file committed yesterday but touching the filesystem "today"
    /// (e.g. a fresh clone) should still appear under yesterday's Created list.
    func test_notesCreatedOnDate_prefersGitAuthorDateOverFilesystemDate() throws {
        try initRepo()
        commitFile("note.md", on: "2026-04-23T10:00:00-04:00")

        // Touch the filesystem timestamps to look like a brand-new file (simulating a clone).
        let fileURL = tempDir.appendingPathComponent("note.md")
        try FileManager.default.setAttributes(
            [.creationDate: Date(), .modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )

        sut.openFolder(tempDir)

        // openFolder dispatches gitDateCache population on gitQueue; spin until it lands.
        let deadline = Date().addingTimeInterval(10)
        while sut.gitDateCache.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(sut.gitDateCache.isEmpty, "git date cache should populate after openFolder")

        let target = date(year: 2026, month: 4, day: 23)
        let created = sut.notesCreatedOnDate(target)

        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.lastPathComponent, "note.md")

        // And the file should NOT appear under today, even though its filesystem dates say so.
        let today = calendar.startOfDay(for: Date())
        let todayCreated = sut.notesCreatedOnDate(today)
        XCTAssertFalse(todayCreated.contains { $0.lastPathComponent == "note.md" },
            "File with yesterday's git date must not leak into today's Created list")
    }

    func test_notesModifiedOnDate_usesCommitterDateOfMostRecentCommit() throws {
        try initRepo()
        commitFile("note.md", on: "2026-04-20T09:00:00-04:00")
        commitFile("note.md", on: "2026-04-23T09:00:00-04:00")

        sut.openFolder(tempDir)
        let deadline = Date().addingTimeInterval(10)
        while sut.gitDateCache.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let modified = sut.notesModifiedOnDate(date(year: 2026, month: 4, day: 23))

        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(modified.first?.lastPathComponent, "note.md")
    }

    /// Opening a new vault must clear the prior `gitDateCache` so date views cannot show
    /// stale paths from another workspace.
    func test_openFolder_switchingVaults_clearsGitDateCacheBeforeRepopulating() throws {
        try initRepo()
        commitFile("first.md", on: "2026-04-10T10:00:00-04:00")

        sut.openFolder(tempDir)
        let deadline1 = Date().addingTimeInterval(10)
        while sut.gitDateCache.isEmpty && Date() < deadline1 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(sut.gitDateCache.isEmpty)

        let otherDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: otherDir) }
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        guard GitService.findGit() != nil else { throw XCTSkip("git not available") }
        runGit(at: otherDir, ["init"])
        runGit(at: otherDir, ["config", "user.email", "test@example.com"])
        runGit(at: otherDir, ["config", "user.name", "Test"])
        runGit(at: otherDir, ["config", "commit.gpgsign", "false"])
        let secondFile = otherDir.appendingPathComponent("second.md")
        try "only in second vault".write(to: secondFile, atomically: true, encoding: .utf8)
        runGit(at: otherDir, ["add", "second.md"])
        runGit(
            at: otherDir,
            ["commit", "-m", "second"],
            env: [
                "GIT_AUTHOR_DATE": "2026-04-11T10:00:00-04:00",
                "GIT_COMMITTER_DATE": "2026-04-11T10:00:00-04:00",
            ]
        )

        sut.openFolder(otherDir)
        let deadline2 = Date().addingTimeInterval(10)
        while sut.gitDateCache.isEmpty && Date() < deadline2 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(sut.gitDateCache.isEmpty, "second vault should populate gitDateCache")
        XCTAssertFalse(
            sut.gitDateCache.keys.contains { $0.path.hasPrefix(tempDir.path) },
            "After switching vaults, gitDateCache must not retain URLs from the previous root"
        )
        XCTAssertEqual(sut.gitDateCache.count, 1)
        XCTAssertTrue(sut.gitDateCache.keys.contains { $0.lastPathComponent == "second.md" })
    }
}
