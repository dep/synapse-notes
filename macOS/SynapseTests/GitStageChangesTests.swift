import XCTest
@testable import Synapse

/// Tests for AppState.stageGitChanges() — the background git-staging step that runs
/// after every saveCurrentFile() call when the autoPush setting is enabled.
///
/// stageGitChanges() is private and runs asynchronously on a serial gitQueue. These
/// tests exercise it through the public saveCurrentFile() entry point, using a real
/// temporary git repository and observing the git staging area via `git status`.
final class GitStageChangesTests: XCTestCase {

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

    // MARK: - Git helpers

    @discardableResult
    private func runGit(_ args: [String], in directory: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.environment = [
            "HOME": NSHomeDirectory(),
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_CONFIG_NOSYSTEM": "1"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func gitStatusOutput(in directory: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = directory
        process.environment = ["HOME": NSHomeDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func initGitRepo(at directory: URL) {
        runGit(["init"], in: directory)
        runGit(["config", "user.email", "test@example.com"], in: directory)
        runGit(["config", "user.name", "Test User"], in: directory)
        // Suppress hints and advice output
        runGit(["config", "advice.detachedHead", "false"], in: directory)
    }

    // MARK: - Guard: no git repo

    func test_saveCurrentFile_withAutoPushEnabled_butNoGitRepo_doesNotCrash() {
        // tempDir is not a git repository; gitService will be nil
        sut.openFolder(tempDir)
        sut.settings.autoPush = true

        let noteURL = tempDir.appendingPathComponent("note.md")
        try! "content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)

        // Must not crash even with autoPush enabled but no git repo backing it
        XCTAssertNoThrow(
            sut.saveCurrentFile(content: "updated content"),
            "saveCurrentFile with autoPush=true but no git repo must not throw"
        )
    }

    func test_stageGitChanges_withNoGitRepo_gitSyncStatusRemainsNotGitRepo() {
        sut.openFolder(tempDir)
        sut.settings.autoPush = true

        let noteURL = tempDir.appendingPathComponent("note.md")
        try! "content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)
        sut.saveCurrentFile(content: "updated content")

        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertEqual(sut.gitSyncStatus, .notGitRepo,
                       "gitSyncStatus should remain .notGitRepo when there is no git repository")
    }

    // MARK: - Guard: autoPush disabled

    func test_saveCurrentFile_withAutoPushDisabled_doesNotStageChanges() throws {
        guard GitService.findGit() != nil else { throw XCTSkip("git not available on this system") }

        initGitRepo(at: tempDir)

        // Create and commit an initial file so the repo has a HEAD commit
        let noteURL = tempDir.appendingPathComponent("note.md")
        try "initial content".write(to: noteURL, atomically: true, encoding: .utf8)
        runGit(["add", "-A"], in: tempDir)
        runGit(["commit", "-m", "init"], in: tempDir)

        sut.openFolder(tempDir)
        sut.settings.autoPush = false
        sut.openFile(noteURL)

        // Modify the file externally then save via AppState
        try "modified content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.saveCurrentFile(content: "modified content")

        // Allow background queue to settle
        Thread.sleep(forTimeInterval: 0.5)

        let status = gitStatusOutput(in: tempDir)
        // With autoPush=false, stageGitChanges is a no-op.
        // The file is modified on disk but NOT in the index.
        // Porcelain output: " M note.md" (space in index column = not staged)
        let isStaged = status.contains("M  note.md")   // staged (index modified)
        XCTAssertFalse(isStaged,
                       "With autoPush disabled, saveCurrentFile must not stage changes. Status: '\(status)'")
    }

    // MARK: - autoPush enabled, git repo present

    func test_saveCurrentFile_withAutoPushEnabled_andGitRepo_stagesChanges() throws {
        guard GitService.findGit() != nil else { throw XCTSkip("git not available on this system") }

        initGitRepo(at: tempDir)

        // Commit an initial version of the file so the working tree starts clean
        let noteURL = tempDir.appendingPathComponent("staged-note.md")
        try "initial content".write(to: noteURL, atomically: true, encoding: .utf8)
        runGit(["add", "-A"], in: tempDir)
        runGit(["commit", "-m", "init"], in: tempDir)

        sut.openFolder(tempDir)
        sut.settings.autoPush = true
        sut.openFile(noteURL)

        // saveCurrentFile writes the content to disk AND calls stageGitChanges()
        sut.saveCurrentFile(content: "updated content by test")

        // stageGitChanges runs on a background queue; give it time to complete
        Thread.sleep(forTimeInterval: 2.0)

        let status = gitStatusOutput(in: tempDir)
        // "M  staged-note.md" means the file is staged in the index (both chars present)
        // or "MM staged-note.md" means staged + additional working-tree changes
        let isStagedInIndex = status.contains("M  staged-note.md") ||
                              status.contains("MM staged-note.md")
        XCTAssertTrue(isStagedInIndex,
                      "With autoPush=true, saveCurrentFile should stage changes via git add -A. Status: '\(status)'")
    }

    func test_saveCurrentFile_withAutoPushEnabled_andNoChanges_doesNotError() throws {
        guard GitService.findGit() != nil else { throw XCTSkip("git not available on this system") }

        initGitRepo(at: tempDir)

        let noteURL = tempDir.appendingPathComponent("clean-note.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)
        runGit(["add", "-A"], in: tempDir)
        runGit(["commit", "-m", "init"], in: tempDir)

        sut.openFolder(tempDir)
        sut.settings.autoPush = true
        sut.openFile(noteURL)

        // Save the same content — no actual changes, hasChanges() returns false
        XCTAssertNoThrow(
            sut.saveCurrentFile(content: "content"),
            "Saving unchanged content must not throw even with autoPush enabled"
        )

        Thread.sleep(forTimeInterval: 0.5)

        let status = gitStatusOutput(in: tempDir)
        XCTAssertTrue(status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "Working tree should remain clean when content is unchanged. Status: '\(status)'")
    }

    // MARK: - saveCurrentFile clears dirty flag regardless of git state

    func test_saveCurrentFile_alwaysClearsDirtyFlag() throws {
        sut.openFolder(tempDir)
        let noteURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)
        sut.fileContent = "hello world"
        sut.isDirty = true

        sut.saveCurrentFile(content: "hello world")

        XCTAssertFalse(sut.isDirty,
                       "saveCurrentFile should always clear isDirty, regardless of git staging outcome")
    }
}
