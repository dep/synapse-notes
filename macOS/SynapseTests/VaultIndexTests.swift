import XCTest
@testable import Synapse

/// Tests that VaultIndex exists as an ObservableObject and holds vault-level data.
final class VaultIndexTests: XCTestCase {

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

    // MARK: - VaultIndex is accessible from AppState

    func test_appState_exposes_vaultIndex() {
        XCTAssertNotNil(sut.vaultIndex)
    }

    func test_vaultIndex_isObservableObject() {
        // VaultIndex must conform to ObservableObject
        _ = sut.vaultIndex.objectWillChange
        XCTAssertTrue(true, "VaultIndex conforms to ObservableObject")
    }

    // MARK: - VaultIndex owns vault-level published properties

    func test_vaultIndex_allFiles_initiallyEmpty() {
        XCTAssertTrue(sut.vaultIndex.allFiles.isEmpty)
    }

    func test_vaultIndex_allProjectFiles_initiallyEmpty() {
        XCTAssertTrue(sut.vaultIndex.allProjectFiles.isEmpty)
    }

    func test_vaultIndex_isIndexing_initiallyFalse() {
        XCTAssertFalse(sut.vaultIndex.isIndexing)
    }

    func test_vaultIndex_lastContentChange_isUUID() {
        XCTAssertNotNil(sut.vaultIndex.lastContentChange)
    }

    // MARK: - AppState properties forward to VaultIndex

    func test_appState_allFiles_forwardsToVaultIndex() {
        sut.openFolder(tempDir)
        let fileURL = tempDir.appendingPathComponent("note.md")
        try! "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()
        XCTAssertEqual(sut.allFiles, sut.vaultIndex.allFiles,
                       "appState.allFiles must equal vaultIndex.allFiles")
    }

    func test_appState_isIndexing_forwardsToVaultIndex() {
        XCTAssertEqual(sut.isIndexing, sut.vaultIndex.isIndexing)
    }

    func test_appState_lastContentChange_forwardsToVaultIndex() {
        XCTAssertEqual(sut.lastContentChange, sut.vaultIndex.lastContentChange)
    }

    // MARK: - VaultIndex fires .filesDidChange notification when allFiles changes

    func test_vaultIndex_firesFilesDidChangeNotification_whenFilesRefreshed() {
        let expectation = expectation(description: "filesDidChange notification fires")
        let file = tempDir.appendingPathComponent("a.md")
        try! "hello".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)

        let token = NotificationCenter.default.addObserver(
            forName: .filesDidChange,
            object: sut.vaultIndex,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        sut.refreshAllFiles()
        waitForExpectations(timeout: 3.0)
    }

    // MARK: - VaultIndex fires .tagsDidChange notification when tags change

    func test_vaultIndex_firesTagsDidChangeNotification_whenContentChanges() {
        let file = tempDir.appendingPathComponent("tagged.md")
        try! "#work idea".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)
        sut.refreshAllFiles()

        let expectation = expectation(description: "tagsDidChange notification fires")
        let token = NotificationCenter.default.addObserver(
            forName: .tagsDidChange,
            object: sut.vaultIndex,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // Simulate a content change that affects tags
        try! "#work #ideas new content".write(to: file, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [file])
        waitForExpectations(timeout: 3.0)
    }

    // MARK: - VaultIndex fires .graphDidChange notification when link structure changes

    func test_vaultIndex_firesGraphDidChangeNotification_whenLinksChange() {
        let file = tempDir.appendingPathComponent("linked.md")
        try! "No links here".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)
        sut.refreshAllFiles()

        let expectation = expectation(description: "graphDidChange notification fires")
        let token = NotificationCenter.default.addObserver(
            forName: .graphDidChange,
            object: sut.vaultIndex,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // Simulate adding a wiki-link
        try! "Now links to [[OtherNote]]".write(to: file, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [file])
        waitForExpectations(timeout: 3.0)
    }
}
