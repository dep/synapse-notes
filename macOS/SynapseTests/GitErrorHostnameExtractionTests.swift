import XCTest
@testable import Synapse

/// Tests for GitError.from(stderr:stdout:operation:) hostname extraction logic.
/// Existing GitErrorTests verify that .sshHostUnknown is returned for host-key errors,
/// but do NOT verify that the correct hostname is extracted from the raw stderr text.
/// These tests cover the hostname-extraction path in detail.
final class GitErrorHostnameExtractionTests: XCTestCase {

    // MARK: - Hostname extraction from stderr

    func test_hostKeyError_extractsHostnameFromECDSALine() {
        let stderr = "ECDSA host key for github.com has changed and you have requested strict checking."
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertEqual(host, "github.com", "Should extract 'github.com' from ECDSA error line")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    func test_hostKeyError_extractsHostnameFromMultiLineStderr() {
        let stderr = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        ECDSA host key for gitlab.example.com has changed and you have requested strict checking.
        Host key verification failed.
        """
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertEqual(host, "gitlab.example.com",
                           "Should extract 'gitlab.example.com' from multi-line stderr")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    func test_hostKeyError_fallsBackToDefaultWhenNoRecognizableHostname() {
        // "Host key verification failed." alone — no line containing a dotted hostname
        let stderr = "Host key verification failed."
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertEqual(host, "the remote host",
                           "Should fall back to 'the remote host' when hostname can't be extracted")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    func test_hostKeyError_excludesShortWordsAsHostname() {
        // "ssh" and "key" are ≤ 3 chars and should be skipped; only "host.example.net" qualifies
        let stderr = "ECDSA host key for host.example.net has changed."
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertEqual(host, "host.example.net",
                           "Short words should be skipped; only dotted word >3 chars should be picked")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    func test_hostKeyError_excludesWordsThatStartWithDash() {
        // Words starting with "-" (e.g. command-line flags) must not be selected as the hostname
        let stderr = "ssh -o StrictHostKeyChecking failed for git.mycompany.io"
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertNotEqual(String(host.prefix(1)), "-",
                              "Hostname must not start with a dash")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    // MARK: - Verify errorDescription embeds the extracted hostname

    func test_errorDescription_containsExtractedHostname() {
        let stderr = "ECDSA host key for bitbucket.org has changed."
        let err = GitError.from(stderr: stderr, stdout: "", operation: "Push")
        if case .sshHostUnknown(let host) = err {
            XCTAssertEqual(host, "bitbucket.org")
            let desc = err.errorDescription ?? ""
            XCTAssertTrue(desc.contains("bitbucket.org"),
                          "errorDescription should contain the extracted hostname")
        } else {
            XCTFail("Expected .sshHostUnknown, got \(err)")
        }
    }

    func test_errorDescription_fallbackContainsRemoteHost() {
        let err = GitError.sshHostUnknown("the remote host")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("the remote host"),
                      "Fallback errorDescription should mention 'the remote host'")
    }
}
