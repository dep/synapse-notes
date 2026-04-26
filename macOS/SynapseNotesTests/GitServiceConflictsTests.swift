import XCTest
@testable import Synapse

/// Tests for GitService.hasConflicts() against a live git repository.
///
/// These tests complement the logic-parity unit test in GitServiceTests that exercises
/// the porcelain-parsing logic inline; here we call service.hasConflicts() on a real
/// repository so regressions in the run() invocation path or porcelain parsing are caught.
final class GitServiceConflictsTests: XCTestCase {

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

    @discardableResult
    private func git(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = tempDir
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func initRepo() throws {
        try git("init")
        try git("config", "user.email", "test@example.com")
        try git("config", "user.name", "Test User")
        try git("config", "commit.gpgsign", "false")
        try git("symbolic-ref", "HEAD", "refs/heads/main")
    }

    private func write(_ content: String, to filename: String) throws {
        let url = tempDir.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Clean repo

    func test_hasConflicts_cleanRepo_returnsFalse() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        try initRepo()
        try write("# Hello\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Initial commit")

        let service = try GitService(repoURL: tempDir)
        XCTAssertFalse(service.hasConflicts(), "A clean repo should have no conflicts")
    }

    // MARK: - Merge conflict → true

    func test_hasConflicts_withMergeConflict_returnsTrue() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        try initRepo()

        try write("shared line\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Initial commit")

        try git("checkout", "-b", "feature")
        try write("feature branch change\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Feature change")

        try git("checkout", "main")
        try write("main branch change\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Main change")

        // Merge will conflict; non-zero exit is expected and intentionally not thrown.
        let mergeProcess = Process()
        mergeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        mergeProcess.arguments = ["merge", "feature"]
        mergeProcess.currentDirectoryURL = tempDir
        mergeProcess.standardOutput = Pipe()
        mergeProcess.standardError = Pipe()
        try mergeProcess.run()
        mergeProcess.waitUntilExit()

        let service = try GitService(repoURL: tempDir)
        XCTAssertTrue(service.hasConflicts(),
                      "A repo with an unresolved merge conflict should report hasConflicts() == true")
    }

    // MARK: - Conflict resolved → false

    func test_hasConflicts_afterResolvingConflict_returnsFalse() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        try initRepo()

        try write("shared line\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Initial commit")

        try git("checkout", "-b", "feature")
        try write("feature content\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Feature commit")

        try git("checkout", "main")
        try write("main content\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Main commit")

        let mergeProcess = Process()
        mergeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        mergeProcess.arguments = ["merge", "feature"]
        mergeProcess.currentDirectoryURL = tempDir
        mergeProcess.standardOutput = Pipe()
        mergeProcess.standardError = Pipe()
        try mergeProcess.run()
        mergeProcess.waitUntilExit()

        let service = try GitService(repoURL: tempDir)
        guard service.hasConflicts() else {
            throw XCTSkip("Merge did not produce a conflict on this system")
        }

        // Resolve: overwrite with clean content, then stage.
        try write("resolved content\n", to: "note.md")
        try git("add", "note.md")

        XCTAssertFalse(service.hasConflicts(),
                       "After staging the resolved file, hasConflicts() should return false")
    }

    // MARK: - Staged but non-conflicting changes

    func test_hasConflicts_stagedNonConflictingChange_returnsFalse() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        try initRepo()

        try write("initial\n", to: "note.md")
        try git("add", "-A")
        try git("commit", "-m", "Initial commit")

        try write("modified\n", to: "note.md")
        try git("add", "-A")

        let service = try GitService(repoURL: tempDir)
        XCTAssertFalse(service.hasConflicts(),
                       "A staged but non-conflicting modification should not report conflicts")
    }
}
