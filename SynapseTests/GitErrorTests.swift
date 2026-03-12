import XCTest
@testable import Synapse

/// Tests for GitError classification (from stderr/stdout), error descriptions,
/// and GitSyncStatus.isInProgress — the core of the app's git error-handling UX.
final class GitErrorTests: XCTestCase {

    // MARK: - GitError.from() SSH authentication

    func test_from_permissionDenied_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "Permission denied (publickey).", stdout: "", operation: "Push")
        XCTAssertEqual(err, .sshAuthFailed)
    }

    func test_from_publickey_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "git@github.com: Permission denied (publickey).", stdout: "", operation: "Push")
        XCTAssertEqual(err, .sshAuthFailed)
    }

    func test_from_signingFailed_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "error: signing failed: No identities found", stdout: "", operation: "Commit")
        XCTAssertEqual(err, .sshAuthFailed)
    }

    func test_from_noIdentities_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "Error connecting to agent: No identities found", stdout: "", operation: "Push")
        XCTAssertEqual(err, .sshAuthFailed)
    }

    // MARK: - GitError.from() SSH host key

    func test_from_hostKeyVerificationFailed_returnsSshHostUnknown() {
        let err = GitError.from(stderr: "Host key verification failed.", stdout: "", operation: "Push")
        if case .sshHostUnknown = err { return }
        XCTFail("Expected .sshHostUnknown, got \(err)")
    }

    func test_from_hostKeyContents_returnsSshHostUnknown() {
        let err = GitError.from(stderr: "ECDSA host key for github.com has changed", stdout: "", operation: "Push")
        if case .sshHostUnknown = err { return }
        XCTFail("Expected .sshHostUnknown, got \(err)")
    }

    // MARK: - GitError.from() network errors

    func test_from_couldNotResolveHostname_returnsCommandFailed_networkMessage() {
        let err = GitError.from(stderr: "Could not resolve hostname github.com: nodename nor servname provided", stdout: "", operation: "Push")
        if case .commandFailed(let msg) = err {
            XCTAssertTrue(msg.contains("reach the remote"), "Expected network message, got: \(msg)")
        } else {
            XCTFail("Expected .commandFailed, got \(err)")
        }
    }

    func test_from_nameOrServiceNotKnown_returnsCommandFailed_networkMessage() {
        let err = GitError.from(stderr: "ssh: Could not resolve hostname: Name or service not known", stdout: "", operation: "Push")
        if case .commandFailed(let msg) = err {
            XCTAssertTrue(msg.contains("reach the remote"), "Expected network message, got: \(msg)")
        } else {
            XCTFail("Expected .commandFailed, got \(err)")
        }
    }

    // MARK: - GitError.from() repository not found

    func test_from_repositoryNotFound_returnsCommandFailed_notFoundMessage() {
        let err = GitError.from(stderr: "ERROR: Repository not found.", stdout: "", operation: "Push")
        if case .commandFailed(let msg) = err {
            XCTAssertTrue(msg.contains("not found"), "Expected 'not found' message, got: \(msg)")
        } else {
            XCTFail("Expected .commandFailed, got \(err)")
        }
    }

    // MARK: - GitError.from() push rejected

    func test_from_rejected_returnsCommandFailed_rejectedMessage() {
        let err = GitError.from(stderr: "! [rejected] main -> main (non-fast-forward)", stdout: "", operation: "Push")
        if case .commandFailed(let msg) = err {
            XCTAssertTrue(msg.contains("rejected") || msg.contains("Pull"), "Expected rejection message, got: \(msg)")
        } else {
            XCTFail("Expected .commandFailed, got \(err)")
        }
    }

    func test_from_nonFastForward_returnsCommandFailed() {
        let err = GitError.from(stderr: "Updates were rejected because the tip of your current branch is behind", stdout: "", operation: "Push")
        if case .commandFailed = err { return }
        XCTFail("Expected .commandFailed, got \(err)")
    }

    // MARK: - GitError.from() fallback behaviour

    func test_from_emptyStderr_usesStdout() {
        let err = GitError.from(stderr: "", stdout: "Permission denied (publickey).", operation: "Push")
        XCTAssertEqual(err, .sshAuthFailed)
    }

    func test_from_unknownError_returnsCommandFailedWithMessage() {
        let err = GitError.from(stderr: "Some unknown git error occurred", stdout: "", operation: "Push")
        if case .commandFailed(let msg) = err {
            XCTAssertEqual(msg, "Some unknown git error occurred")
        } else {
            XCTFail("Expected .commandFailed, got \(err)")
        }
    }

    func test_from_bothEmpty_returnsCommandFailed_genericMessage() {
        let err = GitError.from(stderr: "", stdout: "", operation: "Push")
        XCTAssertEqual(err, .commandFailed("Git command failed."))
    }

    func test_from_whitespaceOnly_returnsCommandFailed_genericMessage() {
        let err = GitError.from(stderr: "   \n  ", stdout: "", operation: "Push")
        XCTAssertEqual(err, .commandFailed("Git command failed."))
    }

    // MARK: - GitError.errorDescription

    func test_errorDescription_gitNotFound_mentionsGit() {
        let desc = GitError.gitNotFound.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Git"), "Expected 'Git' in description, got: \(desc)")
    }

    func test_errorDescription_commandFailed_withMessage_returnsMessage() {
        XCTAssertEqual(GitError.commandFailed("Custom error message").errorDescription, "Custom error message")
    }

    func test_errorDescription_commandFailed_emptyMessage_returnsGeneric() {
        XCTAssertEqual(GitError.commandFailed("").errorDescription, "Git command failed.")
    }

    func test_errorDescription_notARepo_mentionsRepository() {
        let desc = GitError.notARepo.errorDescription ?? ""
        XCTAssertTrue(desc.lowercased().contains("repository") || desc.lowercased().contains("repo"),
                      "Expected 'repository' in description, got: \(desc)")
    }

    func test_errorDescription_sshAuthFailed_mentionsSSH() {
        let desc = GitError.sshAuthFailed.errorDescription ?? ""
        XCTAssertTrue(desc.contains("SSH"), "Expected 'SSH' in description, got: \(desc)")
    }

    func test_errorDescription_sshHostUnknown_containsHostName() {
        let desc = GitError.sshHostUnknown("github.com").errorDescription ?? ""
        XCTAssertTrue(desc.contains("github.com"), "Expected hostname in description, got: \(desc)")
    }

    func test_errorDescription_timeout_containsOperationAndTimedOut() {
        let desc = GitError.timeout("Push").errorDescription ?? ""
        XCTAssertTrue(desc.contains("Push"), "Expected operation name in description, got: \(desc)")
        XCTAssertTrue(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"),
                      "Expected 'timed out' in description, got: \(desc)")
    }

    // MARK: - GitSyncStatus.isInProgress

    func test_isInProgress_cloning_isTrue() {
        XCTAssertTrue(GitSyncStatus.cloning.isInProgress)
    }

    func test_isInProgress_committing_isTrue() {
        XCTAssertTrue(GitSyncStatus.committing.isInProgress)
    }

    func test_isInProgress_pulling_isTrue() {
        XCTAssertTrue(GitSyncStatus.pulling.isInProgress)
    }

    func test_isInProgress_pushing_isTrue() {
        XCTAssertTrue(GitSyncStatus.pushing.isInProgress)
    }

    func test_isInProgress_idle_isFalse() {
        XCTAssertFalse(GitSyncStatus.idle.isInProgress)
    }

    func test_isInProgress_notGitRepo_isFalse() {
        XCTAssertFalse(GitSyncStatus.notGitRepo.isInProgress)
    }

    func test_isInProgress_upToDate_isFalse() {
        XCTAssertFalse(GitSyncStatus.upToDate.isInProgress)
    }

    func test_isInProgress_conflict_isFalse() {
        XCTAssertFalse(GitSyncStatus.conflict("Merge conflict").isInProgress)
    }

    func test_isInProgress_error_isFalse() {
        XCTAssertFalse(GitSyncStatus.error("Some error").isInProgress)
    }

    // MARK: - GitSyncStatus Equatable

    func test_equatable_identicalCases_areEqual() {
        XCTAssertEqual(GitSyncStatus.idle, .idle)
        XCTAssertEqual(GitSyncStatus.notGitRepo, .notGitRepo)
        XCTAssertEqual(GitSyncStatus.cloning, .cloning)
        XCTAssertEqual(GitSyncStatus.committing, .committing)
        XCTAssertEqual(GitSyncStatus.pulling, .pulling)
        XCTAssertEqual(GitSyncStatus.pushing, .pushing)
        XCTAssertEqual(GitSyncStatus.upToDate, .upToDate)
        XCTAssertEqual(GitSyncStatus.conflict("x"), .conflict("x"))
        XCTAssertEqual(GitSyncStatus.error("e"), .error("e"))
    }

    func test_equatable_differentCases_areNotEqual() {
        XCTAssertNotEqual(GitSyncStatus.idle, .cloning)
        XCTAssertNotEqual(GitSyncStatus.conflict("a"), .conflict("b"))
        XCTAssertNotEqual(GitSyncStatus.error("x"), .error("y"))
    }
}
