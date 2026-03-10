import XCTest
@testable import Noted

/// Tests for GitError.from(stderr:stdout:operation:) classification logic
/// and GitError.errorDescription localised messages.
final class GitErrorTests: XCTestCase {

    // MARK: - SSH auth failures

    func test_from_permissionDenied_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "Permission denied (publickey).", stdout: "", operation: "Push")
        guard case .sshAuthFailed = err else { return XCTFail("Expected .sshAuthFailed, got \(err)") }
    }

    func test_from_publickeyKeyword_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "fatal: publickey auth rejected", stdout: "", operation: "Push")
        guard case .sshAuthFailed = err else { return XCTFail("Expected .sshAuthFailed, got \(err)") }
    }

    func test_from_signingFailed_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "error: signing failed: agent refused operation", stdout: "", operation: "Commit")
        guard case .sshAuthFailed = err else { return XCTFail("Expected .sshAuthFailed, got \(err)") }
    }

    func test_from_noIdentities_returnsSshAuthFailed() {
        let err = GitError.from(stderr: "no identities available", stdout: "", operation: "Push")
        guard case .sshAuthFailed = err else { return XCTFail("Expected .sshAuthFailed, got \(err)") }
    }

    func test_from_permissionDenied_caseInsensitive() {
        let err = GitError.from(stderr: "PERMISSION DENIED", stdout: "", operation: "Push")
        guard case .sshAuthFailed = err else { return XCTFail("Expected .sshAuthFailed, got \(err)") }
    }

    // MARK: - SSH host key verification

    func test_from_hostKeyVerificationFailed_returnsSshHostUnknown() {
        let err = GitError.from(stderr: "Host key verification failed", stdout: "", operation: "Clone")
        guard case .sshHostUnknown = err else { return XCTFail("Expected .sshHostUnknown, got \(err)") }
    }

    func test_from_ecdsaHostKey_extractsHostname() {
        let stderr = "ECDSA host key for github.com has changed"
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        guard case .sshHostUnknown(let host) = err else {
            return XCTFail("Expected .sshHostUnknown, got \(err)")
        }
        XCTAssertEqual(host, "github.com")
    }

    func test_from_hostKeyNoHostnameInMessage_usesFallback() {
        // No word containing "." in the host-line → falls back to "the remote host"
        let err = GitError.from(stderr: "Host key verification failed", stdout: "", operation: "Push")
        guard case .sshHostUnknown(let host) = err else {
            return XCTFail("Expected .sshHostUnknown, got \(err)")
        }
        XCTAssertEqual(host, "the remote host")
    }

    func test_from_multilineStderr_extractsHostnameFromCorrectLine() {
        let stderr = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@
        WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED
        @@@@@@@@@@@@@@@@@@@@@@@@@@@
        Host key for bitbucket.org has changed
        """
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Clone")
        guard case .sshHostUnknown(let host) = err else {
            return XCTFail("Expected .sshHostUnknown, got \(err)")
        }
        XCTAssertEqual(host, "bitbucket.org")
    }

    // MARK: - Network errors

    func test_from_couldNotResolveHostname_returnsNetworkError() {
        let err = GitError.from(
            stderr: "ssh: Could not resolve hostname github.com: nodename nor servname provided",
            stdout: "",
            operation: "Push"
        )
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertTrue(msg.contains("network"), "Expected network message, got: \(msg)")
    }

    func test_from_nameOrServiceNotKnown_returnsNetworkError() {
        let err = GitError.from(
            stderr: "Name or service not known",
            stdout: "",
            operation: "Push"
        )
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertTrue(msg.contains("network") || msg.contains("remote"), "Got: \(msg)")
    }

    // MARK: - Repository not found

    func test_from_repositoryNotFound_returnsRepoError() {
        let err = GitError.from(stderr: "ERROR: Repository not found.", stdout: "", operation: "Clone")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertTrue(msg.lowercased().contains("repository") || msg.lowercased().contains("remote"), "Got: \(msg)")
    }

    func test_from_notFound_returnsRepoError() {
        let err = GitError.from(stderr: "fatal: not found", stdout: "", operation: "Clone")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertTrue(msg.lowercased().contains("repository") || msg.lowercased().contains("remote"), "Got: \(msg)")
    }

    // MARK: - Push rejected / non-fast-forward

    func test_from_rejected_returnsPushRejectedMessage() {
        let err = GitError.from(stderr: "! [rejected] main -> main (fetch first)", stdout: "", operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, "Push rejected by remote. Try pulling first to merge remote changes.")
    }

    func test_from_nonFastForward_returnsPushRejectedMessage() {
        let err = GitError.from(stderr: "! [rejected] main -> main (non-fast-forward)", stdout: "", operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, "Push rejected by remote. Try pulling first to merge remote changes.")
    }

    // MARK: - Fallback

    func test_from_unknownError_returnsRawStderrMessage() {
        let stderr = "Something entirely unexpected happened"
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, stderr)
    }

    func test_from_emptyStderr_usesStdoutAsMessage() {
        let stdout = "Some stdout output"
        let err = GitError.from(stderr: "", stdout: stdout, operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, stdout)
    }

    func test_from_emptyStderrAndStdout_returnsGenericMessage() {
        let err = GitError.from(stderr: "", stdout: "", operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, "Git command failed.")
    }

    func test_from_whitespaceOnlyMessage_returnsGenericMessage() {
        let err = GitError.from(stderr: "   \n  \t  ", stdout: "", operation: "Push")
        guard case .commandFailed(let msg) = err else { return XCTFail("Expected .commandFailed, got \(err)") }
        XCTAssertEqual(msg, "Git command failed.")
    }

    // MARK: - errorDescription

    func test_errorDescription_gitNotFound_containsGitNotFound() {
        let desc = GitError.gitNotFound.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("Git not found"), "Got: \(desc!)")
    }

    func test_errorDescription_notARepo() {
        XCTAssertEqual(GitError.notARepo.errorDescription, "The folder is not a git repository.")
    }

    func test_errorDescription_sshAuthFailed_mentionsSSH() {
        let desc = GitError.sshAuthFailed.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.lowercased().contains("ssh"), "Got: \(desc!)")
    }

    func test_errorDescription_sshHostUnknown_containsHostname() {
        let desc = GitError.sshHostUnknown("example.com").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("example.com"), "Got: \(desc!)")
    }

    func test_errorDescription_timeout_containsOperationName() {
        let desc = GitError.timeout("Push").errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("Push"), "Got: \(desc!)")
    }

    func test_errorDescription_commandFailed_emptyString_returnsGenericMessage() {
        XCTAssertEqual(GitError.commandFailed("").errorDescription, "Git command failed.")
    }

    func test_errorDescription_commandFailed_nonEmpty_returnsMessage() {
        XCTAssertEqual(GitError.commandFailed("Custom error").errorDescription, "Custom error")
    }
}
