import XCTest
import Combine
@testable import Synapse

/// Tests that git failures are surfaced to the UI as `gitSyncStatus = .error(...)`
/// instead of being silently swallowed (Issue #255).
///
/// Each test runs against a real temporary git repository (GitServiceLiveTests
/// pattern) and skips gracefully when git is not installed. Failures are induced
/// deterministically by holding `.git/index.lock`, which makes `git add` /
/// `git commit` fail the same way a crashed git process or permission problem would.
final class AppStateGitErrorSurfacingTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Auto-save staging (the empty-catch path)

    func test_autoSaveStaging_whenStageFails_setsErrorStatus() throws {
        let repo = try makeLocalRepo()
        sut.openFolder(repo)

        let note = repo.appendingPathComponent("note.md")
        try "# Note".write(to: note, atomically: true, encoding: .utf8)
        sut.openFile(note)
        sut.settings.autoPush = true

        // Hold the index lock so `git add` fails deterministically.
        holdIndexLock(in: repo)

        let captured = expectStatus(matching: { if case .error = $0 { return true }; return false })

        sut.saveCurrentFile(content: "# Note\n\nchanged content")

        wait(for: [captured.expectation], timeout: 10)
        guard case .error(let message)? = captured.value() else {
            return XCTFail("Expected .error status after a failed auto-save staging")
        }
        XCTAssertTrue(message.contains("Auto-save staging failed"),
                      "Error should identify the failing operation, got: \(message)")
    }

    func test_autoSaveStaging_whenStageSucceeds_clearsPreviousError() throws {
        let repo = try makeLocalRepo()
        sut.openFolder(repo)

        let note = repo.appendingPathComponent("note.md")
        try "# Note".write(to: note, atomically: true, encoding: .utf8)
        sut.openFile(note)
        sut.settings.autoPush = true
        sut.gitSyncStatus = .error("stale failure from an earlier save")

        let captured = expectStatus(matching: { $0 == .idle })

        sut.saveCurrentFile(content: "# Note\n\nrecovered content")

        wait(for: [captured.expectation], timeout: 10)
        XCTAssertEqual(captured.value(), .idle,
                       "A successful staging should clear a stale .error back to .idle")
    }

    // MARK: - pullAndRefresh (local-only WIP auto-commit path)

    func test_pullAndRefresh_localRepo_whenWIPCommitFails_setsErrorStatus() throws {
        let repo = try makeLocalRepo()
        sut.openFolder(repo)

        // Uncommitted change on disk so pullAndRefresh attempts the WIP auto-commit.
        let note = repo.appendingPathComponent("note.md")
        try "# Uncommitted".write(to: note, atomically: true, encoding: .utf8)

        holdIndexLock(in: repo)

        let captured = expectStatus(matching: { if case .error = $0 { return true }; return false })

        sut.pullAndRefresh()

        wait(for: [captured.expectation], timeout: 10)
        guard case .error? = captured.value() else {
            return XCTFail("Expected .error status when the WIP auto-commit fails")
        }
    }

    func test_pullAndRefresh_localRepo_fromErrorState_retriesAndRecoversToIdle() throws {
        let repo = try makeLocalRepo()
        sut.openFolder(repo)
        sut.gitSyncStatus = .error("previous git failure")

        let captured = expectStatus(matching: { $0 == .idle })

        // Clean tree: the WIP commit is a no-op and the refresh succeeds.
        sut.pullAndRefresh()

        wait(for: [captured.expectation], timeout: 10)
        XCTAssertEqual(captured.value(), .idle,
                       ".error must be retryable: a successful CMD-R should recover to .idle")
    }

    // MARK: - pullLatest / performPull (remote pull path)

    func test_pullLatest_whenPullFails_setsErrorStatus() throws {
        let repo = try makeLocalRepo()
        // Point origin at a path that is not a repository so pull fails fast and offline.
        runGit(["remote", "add", "origin", tempDir.appendingPathComponent("missing-remote").path], in: repo)

        let captured = expectStatus(matching: { if case .error = $0 { return true }; return false })

        // openFolder triggers setupGit -> pullLatest against the broken remote.
        sut.openFolder(repo)

        wait(for: [captured.expectation], timeout: 10)
        guard case .error? = captured.value() else {
            return XCTFail("Expected .error status when pulling from a broken remote")
        }
    }

    // MARK: - Helpers

    /// Subscribes to `gitSyncStatus` and fulfills once a published value matches.
    private func expectStatus(
        matching predicate: @escaping (GitSyncStatus) -> Bool
    ) -> (expectation: XCTestExpectation, value: () -> GitSyncStatus?) {
        let exp = expectation(description: "gitSyncStatus matches predicate")
        exp.assertForOverFulfill = false
        var captured: GitSyncStatus?
        sut.$gitSyncStatus
            .sink { status in
                if captured == nil, predicate(status) {
                    captured = status
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)
        return (exp, { captured })
    }

    /// Creates `.git/index.lock` so any staging/committing git command fails.
    private func holdIndexLock(in repo: URL) {
        let lock = repo.appendingPathComponent(".git/index.lock")
        FileManager.default.createFile(atPath: lock.path, contents: Data())
    }

    private func makeLocalRepo() throws -> URL {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        let repo = tempDir.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        runGit(["init"], in: repo)
        runGit(["config", "user.email", "test@example.com"], in: repo)
        runGit(["config", "user.name", "Test"], in: repo)
        runGit(["config", "commit.gpgsign", "false"], in: repo)

        let readme = repo.appendingPathComponent("README.md")
        try "# Test".write(to: readme, atomically: true, encoding: .utf8)
        runGit(["add", "-A"], in: repo)
        runGit(["commit", "-m", "initial"], in: repo)

        guard GitService.isGitRepo(at: repo) else {
            throw XCTSkip("git init failed")
        }
        return repo
    }

    private func runGit(_ args: [String], in url: URL) {
        guard let gitPath = GitService.findGit() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = url
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }
}
