import XCTest
@testable import Noted

/// Tests for GitSyncStatus.isInProgress computed property and Equatable conformance.
/// The isInProgress flag controls whether git-related UI controls are enabled/disabled,
/// so regressions here would silently allow double-push actions or lock the UI permanently.
final class GitSyncStatusTests: XCTestCase {

    // MARK: - isInProgress: cases that should return true

    func test_isInProgress_cloning_returnsTrue() {
        XCTAssertTrue(GitSyncStatus.cloning.isInProgress)
    }

    func test_isInProgress_committing_returnsTrue() {
        XCTAssertTrue(GitSyncStatus.committing.isInProgress)
    }

    func test_isInProgress_pulling_returnsTrue() {
        XCTAssertTrue(GitSyncStatus.pulling.isInProgress)
    }

    func test_isInProgress_pushing_returnsTrue() {
        XCTAssertTrue(GitSyncStatus.pushing.isInProgress)
    }

    // MARK: - isInProgress: all other cases must return false

    func test_isInProgress_notGitRepo_returnsFalse() {
        XCTAssertFalse(GitSyncStatus.notGitRepo.isInProgress)
    }

    func test_isInProgress_idle_returnsFalse() {
        XCTAssertFalse(GitSyncStatus.idle.isInProgress)
    }

    func test_isInProgress_upToDate_returnsFalse() {
        XCTAssertFalse(GitSyncStatus.upToDate.isInProgress)
    }

    func test_isInProgress_conflict_returnsFalse() {
        XCTAssertFalse(GitSyncStatus.conflict("merge conflict in file.md").isInProgress)
    }

    func test_isInProgress_error_returnsFalse() {
        XCTAssertFalse(GitSyncStatus.error("Something went wrong").isInProgress)
    }

    // MARK: - Equatable: simple cases

    func test_equatable_notGitRepo_equalToItself() {
        XCTAssertEqual(GitSyncStatus.notGitRepo, GitSyncStatus.notGitRepo)
    }

    func test_equatable_idle_equalToItself() {
        XCTAssertEqual(GitSyncStatus.idle, GitSyncStatus.idle)
    }

    func test_equatable_cloning_equalToItself() {
        XCTAssertEqual(GitSyncStatus.cloning, GitSyncStatus.cloning)
    }

    func test_equatable_committing_equalToItself() {
        XCTAssertEqual(GitSyncStatus.committing, GitSyncStatus.committing)
    }

    func test_equatable_pulling_equalToItself() {
        XCTAssertEqual(GitSyncStatus.pulling, GitSyncStatus.pulling)
    }

    func test_equatable_pushing_equalToItself() {
        XCTAssertEqual(GitSyncStatus.pushing, GitSyncStatus.pushing)
    }

    func test_equatable_upToDate_equalToItself() {
        XCTAssertEqual(GitSyncStatus.upToDate, GitSyncStatus.upToDate)
    }

    // MARK: - Equatable: associated-value cases

    func test_equatable_conflict_sameMessage_areEqual() {
        XCTAssertEqual(GitSyncStatus.conflict("same"), GitSyncStatus.conflict("same"))
    }

    func test_equatable_conflict_differentMessages_areNotEqual() {
        XCTAssertNotEqual(GitSyncStatus.conflict("a"), GitSyncStatus.conflict("b"))
    }

    func test_equatable_error_sameMessage_areEqual() {
        XCTAssertEqual(GitSyncStatus.error("same"), GitSyncStatus.error("same"))
    }

    func test_equatable_error_differentMessages_areNotEqual() {
        XCTAssertNotEqual(GitSyncStatus.error("a"), GitSyncStatus.error("b"))
    }

    // MARK: - Equatable: cross-case inequality

    func test_equatable_differentCases_areNotEqual() {
        XCTAssertNotEqual(GitSyncStatus.idle, GitSyncStatus.notGitRepo)
        XCTAssertNotEqual(GitSyncStatus.idle, GitSyncStatus.cloning)
        XCTAssertNotEqual(GitSyncStatus.pulling, GitSyncStatus.pushing)
        XCTAssertNotEqual(GitSyncStatus.committing, GitSyncStatus.cloning)
        XCTAssertNotEqual(GitSyncStatus.upToDate, GitSyncStatus.idle)
    }

    func test_equatable_conflictAndError_withSameMessage_areNotEqual() {
        XCTAssertNotEqual(GitSyncStatus.conflict("msg"), GitSyncStatus.error("msg"))
    }
}
