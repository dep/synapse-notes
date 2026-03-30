import XCTest
@testable import Synapse

/// Tests for the WIP auto-save behavior in `pullAndRefresh()` (CMD-R).
///
/// Issue #174: When the user presses CMD-R, any uncommitted local changes must be
/// automatically committed with a "WIP: auto-save before refresh" message *before*
/// the git pull is performed, so no work is ever lost during a sync.
///
/// These tests use a real local git repository with no remote, so `pullAndRefresh()`
/// follows the no-remote path (just `refreshAllFiles()`). What we want to verify is
/// the auto-save/commit step that must happen *before* the pull attempt, regardless
/// of whether a remote exists.
final class PullAndRefreshWIPAutoSaveTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    // MARK: - Setup / Teardown

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

    /// Initializes a local git repo at `tempDir` with an initial commit.
    private func initGitRepo() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        gitRun("init")
        gitRun("config", "user.email", "test@example.com")
        gitRun("config", "user.name", "Test User")
        gitRun("config", "commit.gpgsign", "false")
        gitRun("symbolic-ref", "HEAD", "refs/heads/main")

        let readme = tempDir.appendingPathComponent("README.md")
        try "# Init\n".write(to: readme, atomically: true, encoding: .utf8)
        gitRun("add", "-A")
        gitRun("commit", "-m", "initial commit")
    }

    @discardableResult
    private func gitRun(_ args: String...) -> Int32 {
        guard let gitPath = GitService.findGit() else { return -1 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = tempDir
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func gitLog() -> [String] {
        guard let gitPath = GitService.findGit() else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = ["log", "--oneline", "--format=%s"]
        p.currentDirectoryURL = tempDir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - WIP commit before pull: git has uncommitted disk changes

    func test_pullAndRefresh_withUncommittedDiskChanges_createsWIPCommitBeforePull() throws {
        try initGitRepo()
        sut.openFolder(tempDir)

        // Write a file change directly to disk (not through the editor) — simulates
        // an external modification or a previous in-memory save that wasn't committed.
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "# Uncommitted change\n".write(to: noteFile, atomically: true, encoding: .utf8)
        // Verify git sees this as an uncommitted change before we call pullAndRefresh.
        let service = try GitService(repoURL: tempDir)
        XCTAssertTrue(service.hasChanges(), "Pre-condition: repo should have uncommitted changes")

        sut.pullAndRefresh()

        // Wait for the async git queue to complete.
        let exp = expectation(description: "WIP commit created")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 5)

        let commits = gitLog()
        XCTAssertTrue(
            commits.contains { $0.hasPrefix("WIP:") },
            "pullAndRefresh should create a WIP commit for uncommitted disk changes. Commits: \(commits)"
        )
    }

    // MARK: - WIP commit: dirty in-memory editor content is saved to disk and committed

    func test_pullAndRefresh_withDirtyEditorContent_savesToDiskAndCreatesWIPCommit() throws {
        try initGitRepo()

        // Create an initial file and open it.
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "# Original\n".write(to: noteFile, atomically: true, encoding: .utf8)
        gitRun("add", "-A")
        gitRun("commit", "-m", "add note.md")

        sut.openFolder(tempDir)
        sut.openFile(noteFile)

        // Simulate in-memory unsaved edit.
        sut.fileContent = "# Modified in memory\n"
        sut.isDirty = true

        sut.pullAndRefresh()

        let exp = expectation(description: "WIP commit from dirty editor")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 5)

        let commits = gitLog()
        XCTAssertTrue(
            commits.contains { $0.hasPrefix("WIP:") },
            "pullAndRefresh should flush dirty editor content and create a WIP commit. Commits: \(commits)"
        )

        // The file on disk should also reflect the in-memory content.
        let diskContent = (try? String(contentsOf: noteFile, encoding: .utf8)) ?? ""
        XCTAssertEqual(diskContent, "# Modified in memory\n",
                       "pullAndRefresh should flush dirty in-memory content to disk before committing")
    }

    /// When the split view is focused on one pane, the other pane can still hold unsaved edits in
    /// `paneStates`. CMD-R must flush those too; otherwise the WIP commit omits them and a forced
    /// reload can drop the inactive buffer (see `reloadSelectedFileFromDiskIfNeeded` while dirty).
    func test_pullAndRefresh_withDirtyInactiveSplitPane_flushesThatPaneToDiskAndWIPCommits() throws {
        try initGitRepo()

        let noteFile = tempDir.appendingPathComponent("note.md")
        try "# Original\n".write(to: noteFile, atomically: true, encoding: .utf8)
        gitRun("add", "-A")
        gitRun("commit", "-m", "add note.md")

        sut.openFolder(tempDir)
        sut.openFile(noteFile)
        sut.splitVertically()
        // splitPane leaves focus on pane 1; move to pane 0 and make edits there.
        sut.focusPane(0)
        sut.fileContent = "# Edited in background pane\n"
        sut.isDirty = true
        // Focus the other pane so the dirty buffer lives only in the inactive snapshot.
        sut.focusPane(1)

        XCTAssertTrue(sut.hasUnsavedChanges(), "Pre-condition: inactive pane should still be dirty")

        sut.pullAndRefresh()

        let exp = expectation(description: "WIP commit includes inactive pane flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 5)

        let commits = gitLog()
        XCTAssertTrue(
            commits.contains { $0.hasPrefix("WIP:") },
            "Expected WIP commit after flushing inactive pane. Commits: \(commits)"
        )

        let diskContent = (try? String(contentsOf: noteFile, encoding: .utf8)) ?? ""
        XCTAssertEqual(
            diskContent,
            "# Edited in background pane\n",
            "Inactive pane buffer should be written to disk before the WIP commit"
        )
    }

    // MARK: - No WIP commit when repo is clean

    func test_pullAndRefresh_withNoUncommittedChanges_doesNotCreateWIPCommit() throws {
        try initGitRepo()
        sut.openFolder(tempDir)

        // Ensure repo is clean.
        let service = try GitService(repoURL: tempDir)
        XCTAssertFalse(service.hasChanges(), "Pre-condition: repo should be clean")

        let commitsBefore = gitLog()

        sut.pullAndRefresh()

        let exp = expectation(description: "No spurious WIP commit")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 5)

        let commitsAfter = gitLog()
        XCTAssertEqual(
            commitsBefore.count, commitsAfter.count,
            "pullAndRefresh should NOT create a WIP commit when there are no uncommitted changes"
        )
    }

    // MARK: - No WIP commit when no git repo

    func test_pullAndRefresh_withNoGitRepo_doesNotCrashAndNoWIPCommit() {
        // Open a plain folder (no git repo) — should simply refresh without committing.
        sut.openFolder(tempDir)

        // Should not crash.
        XCTAssertNoThrow(sut.pullAndRefresh())
    }

    // MARK: - WIP commit message format

    func test_pullAndRefresh_wipCommitMessage_startsWithWIPPrefix() throws {
        try initGitRepo()
        sut.openFolder(tempDir)

        let noteFile = tempDir.appendingPathComponent("note.md")
        try "# Some change\n".write(to: noteFile, atomically: true, encoding: .utf8)

        sut.pullAndRefresh()

        let exp = expectation(description: "WIP commit message format")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 5)

        let commits = gitLog()
        let wipCommit = commits.first { $0.hasPrefix("WIP:") }
        XCTAssertNotNil(wipCommit, "Expected a WIP commit to exist")
        XCTAssertTrue(
            wipCommit?.contains("auto-save before refresh") == true,
            "WIP commit message should contain 'auto-save before refresh'. Got: \(wipCommit ?? "nil")"
        )
    }
}
