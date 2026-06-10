import XCTest
@testable import Synapse

/// Tests for the async git-state population in `AppState.setupGit` (Issue #257).
///
/// `setupGit` used to run `git.currentBranch()` and `git.aheadCount()` synchronously on
/// the main thread during `openFolder`, blocking on subprocess exit. They now run on the
/// internal git queue and publish back to the main thread, so these tests open a real
/// temp git repository and wait for `gitBranch` / `gitAheadCount` to populate.
///
/// Pattern follows GitServiceLiveTests (real repos, XCTSkip when git is unavailable).
final class AppStateSetupGitAsyncTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var repoDir: URL!
    var remoteDir: URL!

    /// A branch name that differs from the `AppConstants.defaultBranchName` placeholder,
    /// so the test can distinguish "populated from git" from "still the default".
    private let branchName = "feature/issue-257"

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        repoDir = tempDir.appendingPathComponent("repo", isDirectory: true)
        remoteDir = tempDir.appendingPathComponent("remote.git", isDirectory: true)
        try! FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Runs git with the given arguments in `directory`. Returns true on exit status 0.
    @discardableResult
    private func git(_ args: [String], in directory: URL) -> Bool {
        guard let gitPath = GitService.findGit() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = directory
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Creates a working repo on `branchName` with a local bare remote, upstream tracking,
    /// and exactly one unpushed commit (so `aheadCount() == 1`).
    private func makeRepoOneAheadOfRemote() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }

        git(["init", "--bare"], in: remoteDir)

        git(["init"], in: repoDir)
        git(["config", "user.email", "test@example.com"], in: repoDir)
        git(["config", "user.name", "Test"], in: repoDir)
        git(["config", "commit.gpgsign", "false"], in: repoDir)

        let readme = repoDir.appendingPathComponent("README.md")
        try "# Test".write(to: readme, atomically: true, encoding: .utf8)
        git(["add", "-A"], in: repoDir)
        git(["commit", "-m", "initial"], in: repoDir)
        git(["checkout", "-b", branchName], in: repoDir)

        git(["remote", "add", "origin", remoteDir.path], in: repoDir)
        guard git(["push", "-u", "origin", branchName], in: repoDir) else {
            throw XCTSkip("git push to local bare remote failed")
        }

        // One commit beyond the remote → aheadCount() == 1.
        let note = repoDir.appendingPathComponent("note.md")
        try "# Unpushed".write(to: note, atomically: true, encoding: .utf8)
        git(["add", "-A"], in: repoDir)
        git(["commit", "-m", "unpushed change"], in: repoDir)

        guard GitService.isGitRepo(at: repoDir) else {
            throw XCTSkip("git repo was not initialised (git init may have failed)")
        }
    }

    /// Polls `condition` on the main run loop until it is true or `timeout` elapses.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 15,
                           condition: @escaping () -> Bool) {
        let exp = expectation(description: description)
        exp.assertForOverFulfill = false
        func poll() {
            if condition() {
                exp.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
        wait(for: [exp], timeout: timeout)
    }

    // MARK: - Tests

    func test_openFolder_onGitRepo_populatesBranchAndAheadCountAsynchronously() throws {
        try makeRepoOneAheadOfRemote()

        sut.openFolder(repoDir)

        // gitService is assigned synchronously, so the status leaves .notGitRepo at once.
        XCTAssertNotEqual(sut.gitSyncStatus, .notGitRepo,
                          "gitSyncStatus should leave .notGitRepo synchronously for a real repo")

        // The branch and ahead count are computed off the main thread and published back.
        waitUntil("gitBranch populated from repo") { self.sut.gitBranch == self.branchName }
        XCTAssertEqual(sut.gitBranch, branchName)

        waitUntil("gitAheadCount populated from repo") { self.sut.gitAheadCount == 1 }
        XCTAssertEqual(sut.gitAheadCount, 1,
                       "aheadCount should reflect the one unpushed commit")

        // Let the setupGit-triggered pullLatest settle before teardown removes the repo.
        waitUntil("gitSyncStatus settles to .idle") { self.sut.gitSyncStatus == .idle }
    }

    func test_openFolder_onLocalOnlyGitRepo_populatesBranchAndSettlesToIdle() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }

        git(["init"], in: repoDir)
        git(["config", "user.email", "test@example.com"], in: repoDir)
        git(["config", "user.name", "Test"], in: repoDir)
        git(["config", "commit.gpgsign", "false"], in: repoDir)
        let readme = repoDir.appendingPathComponent("README.md")
        try "# Test".write(to: readme, atomically: true, encoding: .utf8)
        git(["add", "-A"], in: repoDir)
        git(["commit", "-m", "initial"], in: repoDir)
        git(["checkout", "-b", branchName], in: repoDir)

        guard GitService.isGitRepo(at: repoDir) else {
            throw XCTSkip("git repo was not initialised (git init may have failed)")
        }

        sut.openFolder(repoDir)

        waitUntil("gitBranch populated from repo") { self.sut.gitBranch == self.branchName }
        XCTAssertEqual(sut.gitBranch, branchName)
        XCTAssertEqual(sut.gitAheadCount, 0, "No remote → aheadCount stays 0")

        // pullLatest probes hasRemote() off-main; with no remote the status stays .idle.
        XCTAssertEqual(sut.gitSyncStatus, .idle,
                       "Status must remain .idle for a local-only repo (no transient .pulling)")
    }
}
