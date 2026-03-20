import XCTest
@testable import Synapse

/// Tests for `AppState.syncToRemote()` and `AppState.saveAndSyncCurrentFile()` guard
/// conditions.
///
/// `syncToRemote()` is the "save and immediately push" path triggered on every
/// explicit CMD-S save when the vault is connected to a git remote.  The guard
/// conditions (no-op when no gitService, no-op when no remote) were not previously
/// covered, even though the analogous guards on `pullLatest()`, `pushToRemote()`, and
/// `autoPushIfEnabled()` were all tested in AppStateGitGuardTests.
final class AppStateSyncToRemoteTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Open a non-git folder so gitService remains nil and status = .notGitRepo
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - syncToRemote() with no git service

    func test_syncToRemote_withNoGitService_doesNotChangeSyncStatus() {
        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo)

        sut.syncToRemote()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "syncToRemote should be a no-op when gitService is nil")
    }

    func test_syncToRemote_withNoGitService_doesNotTransitionToPushing() {
        sut.syncToRemote()

        XCTAssertNotEqual(sut.gitSyncStatus, .pushing,
                          "syncToRemote must not set status to .pushing without a git repo")
    }

    func test_syncToRemote_withNoGitService_doesNotTransitionToError() {
        sut.syncToRemote()

        if case .error = sut.gitSyncStatus {
            XCTFail("syncToRemote should not produce an error state when gitService is nil")
        }
    }

    // MARK: - syncToRemote() with git repo but no remote

    func test_syncToRemote_withGitRepoButNoRemote_doesNotTransitionToPushing() throws {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }

        // Create a local git repo with no remote configured.
        let gitRepoDir = tempDir.appendingPathComponent("local-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: gitRepoDir, withIntermediateDirectories: true)
        initLocalRepo(at: gitRepoDir)

        guard GitService.isGitRepo(at: gitRepoDir) else {
            throw XCTSkip("git init failed")
        }

        sut.openFolder(gitRepoDir)

        // gitService is now set (it's a real repo), but hasRemote() returns false.
        XCTAssertNotEqual(sut.gitSyncStatus, .notGitRepo,
                          "Pre-condition: gitSyncStatus should not be .notGitRepo with a real repo")

        sut.syncToRemote()

        // The guard `guard let git = gitService, git.hasRemote()` should fire.
        XCTAssertNotEqual(sut.gitSyncStatus, .pushing,
                          "syncToRemote must not set .pushing when the repo has no remote")
    }

    // MARK: - saveAndSyncCurrentFile() delegates correctly

    func test_saveAndSyncCurrentFile_withNoGitService_doesNotCrash() {
        // Open a markdown file so saveCurrentFile has something to save.
        let noteFile = tempDir.appendingPathComponent("note.md")
        try! "# Test".write(to: noteFile, atomically: true, encoding: .utf8)
        sut.openFile(noteFile)

        // Should complete without throwing or crashing.
        XCTAssertNoThrow(sut.saveAndSyncCurrentFile(),
                         "saveAndSyncCurrentFile should not crash when there is no git service")
    }

    func test_saveAndSyncCurrentFile_withNoGitService_statusRemainsNotGitRepo() {
        let noteFile = tempDir.appendingPathComponent("note.md")
        try! "# Test".write(to: noteFile, atomically: true, encoding: .utf8)
        sut.openFile(noteFile)

        sut.saveAndSyncCurrentFile()

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "saveAndSyncCurrentFile should leave git status as .notGitRepo when no git repo exists")
    }

    // MARK: - syncToRemote() does not affect unrelated state

    func test_syncToRemote_doesNotModifySelectedFile() {
        let noteFile = tempDir.appendingPathComponent("note.md")
        try! "# Content".write(to: noteFile, atomically: true, encoding: .utf8)
        sut.openFile(noteFile)

        sut.syncToRemote()

        XCTAssertEqual(sut.selectedFile, noteFile,
                       "syncToRemote should not change the currently selected file")
    }

    func test_syncToRemote_doesNotModifyFileContent() {
        let noteFile = tempDir.appendingPathComponent("note.md")
        try! "# Content".write(to: noteFile, atomically: true, encoding: .utf8)
        sut.openFile(noteFile)
        let contentBefore = sut.fileContent

        sut.syncToRemote()

        XCTAssertEqual(sut.fileContent, contentBefore,
                       "syncToRemote should not modify the in-memory file content")
    }

    // MARK: - Helpers

    private func initLocalRepo(at url: URL) {
        guard let gitPath = GitService.findGit() else { return }

        func run(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitPath)
            p.arguments = args
            p.currentDirectoryURL = url
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
        }

        run(["init"])
        run(["config", "user.email", "test@example.com"])
        run(["config", "user.name", "Test"])
        run(["config", "commit.gpgsign", "false"])

        let readme = url.appendingPathComponent("README.md")
        try? "# Test".write(to: readme, atomically: true, encoding: .utf8)
        run(["add", "-A"])
        run(["commit", "-m", "initial"])
    }
}
