import XCTest
@testable import Synapse

/// Tests for the SSH askpass script that `GitService` writes to Application Support.
///
/// SSH can't show a passphrase dialog in a non-TTY environment (e.g. inside an
/// app sandbox or daemon).  Synapse installs a small `osascript`-based helper at
/// `~/Library/Application Support/Synapse/ssh-askpass.sh` and points the
/// `SSH_ASKPASS` environment variable at it before every git process it spawns.
///
/// If the script is absent, has wrong content, or isn't executable, SSH will
/// silently fail to authenticate passphrase-protected keys, causing every push/
/// pull to the remote to error with "Permission denied (publickey)".
///
/// The script is created lazily as a `private static let` side-effect of the
/// first call to `GitService.runProcess`.  These tests trigger that code path
/// via `hasChanges()` — the cheapest read-only git operation — on a fresh temp
/// repo, then assert on the expected file system state.
final class GitServiceAskpassTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Runs `git <args>` synchronously in `tempDir` (best-effort, no throw).
    @discardableResult
    private func git(_ args: [String]) -> String {
        guard let gitPath = GitService.findGit() else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = tempDir
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Creates a minimal git repo in `tempDir` and returns an initialised `GitService`.
    private func makeGitService() throws -> GitService {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }

        git(["init"])
        git(["config", "user.email", "test@example.com"])
        git(["config", "user.name", "Test"])
        git(["config", "commit.gpgsign", "false"])

        do {
            return try GitService(repoURL: tempDir)
        } catch GitError.gitNotFound {
            throw XCTSkip("git not available on this system")
        } catch GitError.notARepo {
            throw XCTSkip("git repo was not initialised")
        }
    }

    /// The path where Synapse is expected to write the askpass helper.
    private var expectedScriptURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Synapse/ssh-askpass.sh")
    }

    // MARK: - Script existence

    func test_askpassScript_isCreatedAfterFirstGitOperation() throws {
        let service = try makeGitService()
        _ = service.hasChanges()   // triggers the first runProcess call

        guard let scriptURL = expectedScriptURL else {
            return XCTFail("Could not determine Application Support path")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "SSH askpass script must exist at \(scriptURL.path) after a git operation"
        )
    }

    // MARK: - Script content

    func test_askpassScript_hasPosixShebang() throws {
        let service = try makeGitService()
        _ = service.hasChanges()

        guard let scriptURL = expectedScriptURL else { return XCTFail("No app support path") }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Askpass script not present — skipping content tests")
        }

        let content = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#!/bin/sh"),
                      "Script must begin with a POSIX sh shebang")
    }

    func test_askpassScript_invokesOsascript() throws {
        let service = try makeGitService()
        _ = service.hasChanges()

        guard let scriptURL = expectedScriptURL else { return XCTFail("No app support path") }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Askpass script not present — skipping content tests")
        }

        let content = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(content.contains("osascript"),
                      "Script must use osascript to display the native macOS dialog")
    }

    func test_askpassScript_showsSSHKeyAuthenticationTitle() throws {
        let service = try makeGitService()
        _ = service.hasChanges()

        guard let scriptURL = expectedScriptURL else { return XCTFail("No app support path") }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Askpass script not present — skipping content tests")
        }

        let content = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(content.contains("SSH Key Authentication"),
                      "Script dialog must show the title 'SSH Key Authentication'")
    }

    // MARK: - Script permissions

    func test_askpassScript_isExecutable() throws {
        let service = try makeGitService()
        _ = service.hasChanges()

        guard let scriptURL = expectedScriptURL else { return XCTFail("No app support path") }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Askpass script not present — skipping permission test")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0
        let executableBits = 0o111
        XCTAssertNotEqual(permissions & executableBits, 0,
                          "Askpass script must have executable bits set (expected 0o755, got \(String(permissions, radix: 8)))")
    }

    func test_askpassScript_hasExpectedPermissions() throws {
        let service = try makeGitService()
        _ = service.hasChanges()

        guard let scriptURL = expectedScriptURL else { return XCTFail("No app support path") }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Askpass script not present — skipping permission test")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(permissions, 0o755,
                       "Askpass script must have 755 permissions so SSH can execute it")
    }
}
