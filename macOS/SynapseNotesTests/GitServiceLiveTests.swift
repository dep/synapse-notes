import XCTest
@testable import Synapse

/// Tests for GitService operations that require a live (initialized) git repository.
/// These tests create a real git repo in a temp directory and exercise the instance
/// methods that run actual git commands: `hasChanges`, `currentBranch`, `hasRemote`,
/// `aheadCount`, and `stageAll`.
///
/// Each test skips gracefully when git is not installed on the machine.
final class GitServiceLiveTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Initialize a real git repository; skip silently if git is not available.
        guard GitService.findGit() != nil else { return }
        initBareRepo()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Setup helpers

    /// Runs `git init` and sets minimal config so commits work.
    private func initBareRepo() {
        guard let gitPath = GitService.findGit() else { return }

        func run(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitPath)
            p.arguments = args
            p.currentDirectoryURL = tempDir
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
        }

        run(["init"])
        run(["config", "user.email", "test@example.com"])
        run(["config", "user.name", "Test"])
        run(["config", "commit.gpgsign", "false"])

        // Create an initial commit so HEAD and branch resolution work.
        let readme = tempDir.appendingPathComponent("README.md")
        try? "# Test".write(to: readme, atomically: true, encoding: .utf8)
        run(["add", "-A"])
        run(["commit", "-m", "initial"])
    }

    /// Creates and returns a `GitService` for `tempDir`, skipping the test if git
    /// is not installed or if the repo was not initialised successfully.
    private func makeService() throws -> GitService {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        do {
            return try GitService(repoURL: tempDir)
        } catch GitError.gitNotFound {
            throw XCTSkip("git not available on this system")
        } catch GitError.notARepo {
            throw XCTSkip("git repo was not initialised (git init may have failed)")
        }
    }

    // MARK: - hasChanges

    func test_hasChanges_returnsFalseOnCleanRepo() throws {
        let service = try makeService()

        XCTAssertFalse(service.hasChanges(),
                       "A freshly committed repo should have no changes")
    }

    func test_hasChanges_returnsTrueAfterCreatingFile() throws {
        let service = try makeService()

        let newFile = tempDir.appendingPathComponent("new-note.md")
        try "# New".write(to: newFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(service.hasChanges(),
                      "Adding an untracked file should be detected as a change")
    }

    func test_hasChanges_returnsTrueAfterModifyingTrackedFile() throws {
        let service = try makeService()

        // README.md was committed in setUp; modify it now.
        let readme = tempDir.appendingPathComponent("README.md")
        try "# Modified".write(to: readme, atomically: true, encoding: .utf8)

        XCTAssertTrue(service.hasChanges(),
                      "Modifying a tracked file should be detected as a change")
    }

    func test_hasChanges_returnsFalseAfterStagingAndCommitting() throws {
        let service = try makeService()

        let newFile = tempDir.appendingPathComponent("staged.md")
        try "staged content".write(to: newFile, atomically: true, encoding: .utf8)

        try service.stageAll()
        try service.commit(message: "add staged file")

        XCTAssertFalse(service.hasChanges(),
                       "After committing, the working tree should be clean")
    }

    // MARK: - currentBranch

    func test_currentBranch_returnsNonEmptyString() throws {
        let service = try makeService()

        let branch = service.currentBranch()

        XCTAssertFalse(branch.isEmpty,
                       "currentBranch() should return a non-empty branch name")
    }

    func test_currentBranch_returnsDefaultBranchName() throws {
        let service = try makeService()

        let branch = service.currentBranch()

        // Modern git defaults to "main"; older git defaults to "master".
        XCTAssertTrue(branch == "main" || branch == "master",
                      "Default branch should be 'main' or 'master', got: \(branch)")
    }

    // MARK: - hasRemote

    func test_hasRemote_returnsFalseWithNoRemoteConfigured() throws {
        let service = try makeService()

        XCTAssertFalse(service.hasRemote(),
                       "A freshly initialised local repo should have no remotes")
    }

    // MARK: - aheadCount

    func test_aheadCount_returnsZeroWithNoRemote() throws {
        let service = try makeService()

        // No remote → no upstream → aheadCount should short-circuit to 0.
        XCTAssertEqual(service.aheadCount(), 0,
                       "aheadCount should be 0 when hasRemote() is false")
    }

    // MARK: - stageAll

    func test_stageAll_doesNotThrowOnCleanRepo() throws {
        let service = try makeService()

        XCTAssertNoThrow(try service.stageAll(),
                         "stageAll on a clean repo should succeed silently")
    }

    func test_stageAll_stagesNewFiles() throws {
        let service = try makeService()

        let newFile = tempDir.appendingPathComponent("to-stage.md")
        try "to stage".write(to: newFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(service.hasChanges())
        XCTAssertNoThrow(try service.stageAll())
        // After staging (but before committing) the file still shows as a change.
        XCTAssertTrue(service.hasChanges(),
                      "Staged-but-uncommitted file should still appear as a change")
    }

    func test_stageAndCommit_producesCleanWorkingTree() throws {
        let service = try makeService()

        let newFile = tempDir.appendingPathComponent("commit-me.md")
        try "commit content".write(to: newFile, atomically: true, encoding: .utf8)

        try service.stageAll()
        try service.commit(message: "test commit")

        XCTAssertFalse(service.hasChanges(),
                       "After stage + commit the working tree should be clean")
    }
}
