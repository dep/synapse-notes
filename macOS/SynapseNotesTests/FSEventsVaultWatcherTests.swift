import XCTest
import Combine
@testable import Synapse

/// Tests for Issue #145: FSEvents recursive vault watcher.
///
/// Validates that:
///  - The vault watcher detects file changes in deeply nested subdirectories.
///  - An external edit to the selected file causes the editor content to reload.
///  - No 0.75 s polling timer exists on the AppState (filePollCancellable removed).
///  - Events are debounced so rapid back-to-back changes produce only one rebuild.
final class FSEventsVaultWatcherTests: XCTestCase {

    var sut: AppState!
    var vaultDir: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        sut = AppState()
        vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: vaultDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(at relativePath: String, content: String = "hello") -> URL {
        let url = vaultDir.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Deeply nested file change triggers allFiles rebuild

    /// A file created inside a deeply nested subdirectory should be picked up by
    /// the watcher and reflected in `allFiles` within a reasonable timeout.
    func test_fileCreatedInDeepSubdirectory_isPickedUpByWatcher() throws {
        // Pre-create the vault with one file so openFolder has something to scan.
        makeFile(at: "top.md")
        sut.openFolder(vaultDir)

        // Wait for the initial scan to complete.
        let initialScanExpectation = expectation(description: "initial scan completes")
        sut.$allFiles
            .first(where: { !$0.isEmpty })
            .sink { _ in initialScanExpectation.fulfill() }
            .store(in: &cancellables)
        wait(for: [initialScanExpectation], timeout: 5.0)

        let beforeCount = sut.allFiles.count

        // Now create a new file in a deeply nested subdirectory.
        let deepDir = vaultDir
            .appendingPathComponent("a/b/c/d", isDirectory: true)
        try! FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let deepFile = deepDir.appendingPathComponent("deep.md")
        try! "deep content".write(to: deepFile, atomically: true, encoding: .utf8)

        // The watcher should fire and rebuild allFiles to include the new file.
        let watcherExpectation = expectation(description: "deep file detected")
        sut.$allFiles
            .first(where: { $0.count > beforeCount })
            .sink { _ in watcherExpectation.fulfill() }
            .store(in: &cancellables)

        wait(for: [watcherExpectation], timeout: 5.0)

        XCTAssertTrue(sut.allFiles.contains(deepFile),
                      "allFiles should contain the deeply nested file after it's created")
    }

    // MARK: - External edit to selected file causes content reload

    /// When the selected file is modified externally (on disk), the watcher
    /// should trigger a content reload without a polling timer.
    func test_externalEditToSelectedFile_reloadsContent() throws {
        let file = makeFile(at: "note.md", content: "original")
        sut.openFolder(vaultDir)

        // Wait for initial scan.
        let scanExp = expectation(description: "scan done")
        sut.$allFiles.first(where: { !$0.isEmpty }).sink { _ in scanExp.fulfill() }.store(in: &cancellables)
        wait(for: [scanExp], timeout: 5.0)

        sut.openFile(file)

        // Give startWatching a moment to register.
        Thread.sleep(forTimeInterval: 0.1)

        // Overwrite the file externally.
        try! "updated externally".write(to: file, atomically: true, encoding: .utf8)

        // Expect fileContent to eventually reflect the new on-disk content.
        let reloadExp = expectation(description: "file content reloaded")
        sut.$fileContent
            .first(where: { $0 == "updated externally" })
            .sink { _ in reloadExp.fulfill() }
            .store(in: &cancellables)

        wait(for: [reloadExp], timeout: 5.0)

        XCTAssertEqual(sut.fileContent, "updated externally")
    }

    // MARK: - No polling timer

    /// AppState must not create a recurring polling timer. The `hasPollingTimer`
    /// property should return false after opening a folder and a file.
    func test_noPollingTimer_afterOpeningFolderAndFile() {
        let file = makeFile(at: "poll.md", content: "x")
        sut.openFolder(vaultDir)

        let scanExp = expectation(description: "scan done")
        sut.$allFiles.first(where: { !$0.isEmpty }).sink { _ in scanExp.fulfill() }.store(in: &cancellables)
        wait(for: [scanExp], timeout: 5.0)

        sut.openFile(file)

        XCTAssertFalse(sut.hasPollingTimer,
                       "hasPollingTimer must be false — polling timer should not exist")
    }

    // MARK: - Rapid changes are debounced

    /// Multiple rapid file events should result in at most a small number of
    /// `allFiles` reassignments (not one per event), demonstrating debouncing.
    func test_rapidFileChanges_areDebounced() throws {
        makeFile(at: "seed.md")
        sut.openFolder(vaultDir)

        let scanExp = expectation(description: "initial scan")
        sut.$allFiles.first(where: { !$0.isEmpty }).sink { _ in scanExp.fulfill() }.store(in: &cancellables)
        wait(for: [scanExp], timeout: 5.0)

        // Count how many times allFiles is reassigned while we create 10 files in quick succession.
        var assignmentCount = 0
        sut.$allFiles
            .dropFirst() // ignore current value
            .sink { _ in assignmentCount += 1 }
            .store(in: &cancellables)

        for i in 0..<10 {
            makeFile(at: "rapid_\(i).md", content: "burst")
            // Spin the run loop briefly so dispatched work can execute between creates.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }

        // Wait long enough for the debounced rebuild to complete, keeping the run loop alive
        // so main-thread dispatch work from the FSEvents handler can execute.
        let allFilesExp = expectation(description: "all files present")
        sut.$allFiles
            .first(where: { $0.count == 11 })
            .sink { _ in allFilesExp.fulfill() }
            .store(in: &cancellables)

        wait(for: [allFilesExp], timeout: 5.0)

        // With a 200-300 ms debounce the 10 rapid creates should collapse into
        // far fewer rebuilds (ideally 1-3). We allow up to 5 as a generous bound.
        XCTAssertLessThanOrEqual(assignmentCount, 5,
            "Rapid changes should be debounced — got \(assignmentCount) allFiles reassignments for 10 rapid creates")
        XCTAssertEqual(sut.allFiles.count, 11, // seed.md + 10 rapid files
            "All files should eventually appear after debounced rebuild")
    }
}
