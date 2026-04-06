import XCTest
@testable import Synapse

/// Tests git sync status flags used to disable UI while network/git work is in flight.
final class GitSyncStatusTests: XCTestCase {

    func test_isInProgress_trueForActiveOperations() {
        XCTAssertTrue(GitSyncStatus.cloning.isInProgress)
        XCTAssertTrue(GitSyncStatus.committing.isInProgress)
        XCTAssertTrue(GitSyncStatus.pulling.isInProgress)
        XCTAssertTrue(GitSyncStatus.pushing.isInProgress)
    }

    func test_isInProgress_falseForIdleStates() {
        XCTAssertFalse(GitSyncStatus.notGitRepo.isInProgress)
        XCTAssertFalse(GitSyncStatus.idle.isInProgress)
        XCTAssertFalse(GitSyncStatus.upToDate.isInProgress)
        XCTAssertFalse(GitSyncStatus.conflict("x").isInProgress)
        XCTAssertFalse(GitSyncStatus.error("y").isInProgress)
    }
}
