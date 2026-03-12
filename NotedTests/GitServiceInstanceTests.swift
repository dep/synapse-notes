import XCTest
@testable import Noted

/// Tests for `GitService` instance methods that run real git commands against a
/// temporary repository.  All tests skip gracefully when git is not installed,
/// which is acceptable in minimal CI/CD environments without Xcode Command Line Tools.
final class GitServiceInstanceTests: XCTestCase {

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

    /// Initialises a real git repo in `tempDir` with minimal identity config,
    /// then returns a `GitService` pointing at it.
    private func makeGitService() throws -> GitService {
        guard let gitPath = GitService.findGit() else {
            throw XCTSkip("git not available on this system")
        }

        try runShellGit(gitPath, ["init", tempDir.path], in: nil)
        try runShellGit(gitPath, ["config", "--local", "user.email", "test@example.com"])
        try runShellGit(gitPath, ["config", "--local", "user.name", "Test User"])

        do {
            return try GitService(repoURL: tempDir)
        } catch GitError.gitNotFound {
            throw XCTSkip("git not available on this system")
        }
    }

    @discardableResult
    private func runShellGit(_ gitPath: String, _ args: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = directory ?? tempDir
        process.environment = ProcessInfo.processInfo.environment
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - hasChanges()

    func test_hasChanges_freshRepoWithNoStagedFiles_returnsFalse() throws {
        let git = try makeGitService()
        // Untracked files are not shown with --porcelain unless staged
        XCTAssertFalse(git.hasChanges(), "A repo with no staged changes should report hasChanges = false")
    }

    func test_hasChanges_afterStagingAFile_returnsTrue() throws {
        let git = try makeGitService()
        guard let gitPath = GitService.findGit() else { throw XCTSkip("git not available") }

        let file = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        try runShellGit(gitPath, ["add", "note.md"])

        XCTAssertTrue(git.hasChanges(), "Staging a file should cause hasChanges to return true")
    }

    // MARK: - currentBranch()

    func test_currentBranch_afterInit_returnsNonEmptyString() throws {
        let git = try makeGitService()
        let branch = git.currentBranch()
        XCTAssertFalse(branch.isEmpty, "currentBranch should return a non-empty string after git init")
    }

    func test_currentBranch_afterInit_returnsValidBranchName() throws {
        let git = try makeGitService()
        let branch = git.currentBranch()
        // git init creates either "main" or "master" depending on global config
        XCTAssertTrue(
            branch == "main" || branch == "master" || !branch.isEmpty,
            "After git init, branch should be 'main', 'master', or another valid name, got: '\(branch)'"
        )
    }

    // MARK: - hasRemote()

    func test_hasRemote_freshRepoWithNoRemotes_returnsFalse() throws {
        let git = try makeGitService()
        XCTAssertFalse(git.hasRemote(), "A freshly initialised repo without any remotes should return false")
    }

    // MARK: - hasConflicts()

    func test_hasConflicts_cleanRepo_returnsFalse() throws {
        let git = try makeGitService()
        XCTAssertFalse(git.hasConflicts(), "A clean repo with no conflict markers should return false")
    }

    // MARK: - stageAll() + commit()

    func test_stageAll_thenCommit_producesCommitAndClearsChanges() throws {
        let git = try makeGitService()
        guard let gitPath = GitService.findGit() else { throw XCTSkip("git not available") }

        let file = tempDir.appendingPathComponent("note.md")
        try "hello world".write(to: file, atomically: true, encoding: .utf8)

        try git.stageAll()
        XCTAssertTrue(git.hasChanges(), "Staged file should appear as pending changes before committing")

        try git.commit(message: "test: initial commit")

        XCTAssertFalse(git.hasChanges(), "After committing all staged changes, hasChanges should return false")

        let log = try runShellGit(gitPath, ["log", "--oneline"])
        XCTAssertTrue(log.contains("initial commit"), "Commit should be visible in git log, got: \(log)")
    }

    // MARK: - aheadCount()

    func test_aheadCount_repoWithNoRemote_returnsZero() throws {
        let git = try makeGitService()
        XCTAssertEqual(git.aheadCount(), 0, "aheadCount should be 0 when there is no remote tracking branch")
    }
}
