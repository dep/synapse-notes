import XCTest
@testable import Synapse

/// Tests for the guard conditions inside AppState's git-integration methods:
///   - `autoPushIfEnabled()` — must no-op when autoPush is off or gitService is nil
///   - `pullLatest()` — must no-op when gitService is nil or sync is already in progress
///   - `pushToRemote()` — must no-op when gitService is nil or no remote
///
/// None of these tests require a live git server; they exercise only the early-return
/// paths that protect against redundant or impossible operations. Breakage here causes
/// double-push races, unexpected state transitions, or crashes when the app has no git.
final class AppStateGitGuardTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // openFolder on a non-git directory: gitService stays nil, gitSyncStatus = .notGitRepo
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - autoPushIfEnabled guards

    func test_autoPushIfEnabled_whenAutoPushDisabled_doesNotChangeSyncStatus() {
        sut.settings.autoPush = false
        let before = sut.gitSyncStatus

        sut.autoPushIfEnabled()

        XCTAssertEqual(sut.gitSyncStatus, before,
                       "autoPushIfEnabled should be a no-op when autoPush is false")
    }

    func test_autoPushIfEnabled_whenAutoPushEnabled_butNoGitService_doesNotTransitionToPushing() {
        sut.settings.autoPush = true
        // tempDir is not a git repo, so gitService is nil after openFolder

        sut.autoPushIfEnabled()

        XCTAssertNotEqual(sut.gitSyncStatus, .pushing,
                          "Should not transition to .pushing without a gitService")
    }

    func test_autoPushIfEnabled_withNoGitRepo_statusRemainsNotGitRepo() {
        sut.settings.autoPush = true

        sut.autoPushIfEnabled()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "Status should remain .notGitRepo when there is no git repo")
    }

    func test_autoPushIfEnabled_autoPushFalse_statusUnchangedRegardlessOfGitState() {
        sut.settings.autoPush = false
        sut.gitSyncStatus = .idle

        sut.autoPushIfEnabled()

        XCTAssertEqual(sut.gitSyncStatus, .idle)
    }

    // MARK: - pullLatest guards

    func test_pullLatest_withNoGitService_doesNotChangeSyncStatus() {
        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo)

        sut.pullLatest()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "pullLatest should be a no-op without a gitService")
    }

    func test_pullLatest_withStatusAlreadyPulling_doesNotReenterPull() {
        // Manually set status to .pulling to simulate an in-progress pull
        sut.gitSyncStatus = .pulling

        sut.pullLatest()

        XCTAssertEqual(sut.gitSyncStatus, .pulling,
                       "pullLatest should not interrupt an in-progress pull")
    }

    func test_pullLatest_withStatusPushing_doesNotStartNewPull() {
        sut.gitSyncStatus = .pushing

        sut.pullLatest()

        XCTAssertEqual(sut.gitSyncStatus, .pushing,
                       "pullLatest must not start when another sync operation is active")
    }

    func test_pullLatest_withStatusConflict_doesNotStartNewPull() {
        sut.gitSyncStatus = .conflict("Merge conflict")

        sut.pullLatest()

        XCTAssertEqual(sut.gitSyncStatus, .conflict("Merge conflict"),
                       "pullLatest must not clobber a conflict state")
    }

    // MARK: - pushToRemote guards

    func test_pushToRemote_withNoGitService_doesNotChangeSyncStatus() {
        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo)

        sut.pushToRemote()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "pushToRemote should be a no-op without a gitService")
    }

    // MARK: - Combined settings / status guards

    func test_gitSyncStatus_initialState_isNotGitRepo_forNonGitFolder() {
        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "A folder without .git should have status .notGitRepo")
    }

    func test_gitBranch_defaultsToMain_forNonGitFolder() {
        XCTAssertEqual(sut.gitBranch, "main",
                       "gitBranch should default to 'main' when no git repo is present")
    }

    func test_gitAheadCount_defaultsToZero_forNonGitFolder() {
        XCTAssertEqual(sut.gitAheadCount, 0,
                       "gitAheadCount should default to 0 when no git repo is present")
    }

    func test_exitVault_resetsGitState() {
        sut.gitSyncStatus = .idle
        sut.gitBranch = "feature/test"
        sut.gitAheadCount = 3

        sut.exitVault()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo)
        XCTAssertEqual(sut.gitBranch, "main")
        XCTAssertEqual(sut.gitAheadCount, 0)
    }
}
