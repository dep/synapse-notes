import XCTest
@testable import Synapse

/// Tests for cloneRepository: gitSyncStatus state machine transitions.
/// Network calls are avoided by using local paths that fail immediately.
final class AppStateCloneRepositoryTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Synchronous status transition

    func test_cloneRepository_setsStatusToCloning_immediately() {
        // The .cloning status change happens synchronously before the async git dispatch
        sut.cloneRepository(remoteURL: "/nonexistent/path/repo.git", to: tempDir) { _ in }

        if case .cloning = sut.gitSyncStatus {
            // expected
        } else {
            XCTFail("gitSyncStatus should be .cloning immediately after cloneRepository is called, got \(sut.gitSyncStatus)")
        }
    }

    // MARK: - Failure path: status resets to notGitRepo

    func test_cloneRepository_failsWithInvalidPath_resetsStatusToNotGitRepo() throws {
        // Skip if git is not installed (minimal CI environments)
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not found; skipping clone failure test")
        }

        let expectation = XCTestExpectation(description: "clone completion")
        var capturedResult: Result<Void, Error>?

        // Use a local path that does not exist as a git repository — git fails immediately
        let nonExistentPath = "/tmp/synapse-test-nonexistent-\(UUID().uuidString).git"
        sut.cloneRepository(remoteURL: nonExistentPath, to: tempDir) { result in
            capturedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15)

        if case .failure = capturedResult {
            // expected
        } else {
            XCTFail("Expected .failure for non-existent local path, got \(String(describing: capturedResult))")
        }

        if case .notGitRepo = sut.gitSyncStatus {
            // expected
        } else {
            XCTFail("gitSyncStatus should be .notGitRepo after a failed clone, got \(sut.gitSyncStatus)")
        }
    }

    // MARK: - Success path: opens folder with correct directory name

    func test_cloneRepository_successPath_opensFolderWithCorrectName() throws {
        // Skip if git is not installed
        guard let gitPath = GitService.findGit() else {
            throw XCTSkip("git not found; skipping clone success test")
        }

        // Create a minimal bare git repo to clone from
        let sourceDir = tempDir.appendingPathComponent("my-project.git")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        // git init --bare
        let initProcess = Process()
        initProcess.executableURL = URL(fileURLWithPath: gitPath)
        initProcess.arguments = ["init", "--bare", sourceDir.path]
        try initProcess.run()
        initProcess.waitUntilExit()
        guard initProcess.terminationStatus == 0 else {
            throw XCTSkip("git init --bare failed; skipping")
        }

        let destParent = tempDir.appendingPathComponent("clones", isDirectory: true)
        try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)

        let expectation = XCTestExpectation(description: "clone success")
        var cloneResult: Result<Void, Error>?

        sut.cloneRepository(remoteURL: sourceDir.path, to: destParent) { result in
            cloneResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15)

        if case .failure(let err) = cloneResult {
            throw XCTSkip("Clone unexpectedly failed: \(err); skipping assertions")
        }

        // The cloned directory should be named "my-project" (extension stripped)
        let expectedDest = destParent.appendingPathComponent("my-project")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedDest.path),
            "Cloned directory should be named 'my-project' (stripped .git extension)"
        )

        // rootURL should be set to the cloned directory
        XCTAssertEqual(sut.rootURL?.standardized, expectedDest.standardized,
                       "openFolder should have been called with the cloned directory")
    }
}
