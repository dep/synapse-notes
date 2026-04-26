import XCTest
@testable import Synapse

/// Tests for the "tap pinned folder → collapse others, focus this one" behaviour.
/// Covers AppState.expandAndScrollToFolder and the focusPinnedFolder signal.
final class AppStatePinnedFolderFocusTests: XCTestCase {

    var appState: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        appState = AppState()
        appState.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        appState = nil
        super.tearDown()
    }

    // MARK: - focusPinnedFolder signal

    func test_expandAndScrollToFolder_setsFocusPinnedFolder() {
        let folder = makeFolder("Projects")
        XCTAssertNil(appState.focusPinnedFolder)

        appState.expandAndScrollToFolder(folder)

        XCTAssertEqual(appState.focusPinnedFolder, folder)
    }

    func test_expandAndScrollToFolder_doesNotOpenFile() {
        // Should not change selectedFile — that's the old behaviour we replaced.
        let folder = makeFolder("Projects")
        appState.expandAndScrollToFolder(folder)

        XCTAssertNil(appState.selectedFile)
    }

    func test_expandAndScrollToFolder_differentFolder_updatesSignal() {
        let folderA = makeFolder("A")
        let folderB = makeFolder("B")

        appState.expandAndScrollToFolder(folderA)
        XCTAssertEqual(appState.focusPinnedFolder, folderA)

        appState.focusPinnedFolder = nil   // simulate FileTreeView consuming the signal

        appState.expandAndScrollToFolder(folderB)
        XCTAssertEqual(appState.focusPinnedFolder, folderB)
    }

    func test_focusPinnedFolder_isPublished() {
        // Verify that assigning focusPinnedFolder triggers objectWillChange
        // (i.e. it's @Published and will drive SwiftUI updates).
        let folder = makeFolder("Watch")
        var fired = false
        let cancellable = appState.objectWillChange.sink { fired = true }

        appState.expandAndScrollToFolder(folder)

        XCTAssertTrue(fired, "objectWillChange should fire when focusPinnedFolder is set")
        cancellable.cancel()
    }

    func test_focusPinnedFolder_canBeResetToNil() {
        let folder = makeFolder("Reset")
        appState.expandAndScrollToFolder(folder)
        XCTAssertNotNil(appState.focusPinnedFolder)

        appState.focusPinnedFolder = nil

        XCTAssertNil(appState.focusPinnedFolder)
    }

    func test_expandAndScrollToFolder_withNonExistentFolder_stillSetsSignal() {
        // Even if the folder doesn't exist on disk, the signal should be set —
        // FileTreeView is responsible for handling missing nodes gracefully.
        let ghost = tempDir.appendingPathComponent("ghost", isDirectory: true)

        appState.expandAndScrollToFolder(ghost)

        XCTAssertEqual(appState.focusPinnedFolder, ghost)
    }

    // MARK: - Pinned folder integration

    func test_pinnedFolder_expandAndScrollToFolder_setsSignal() {
        let folder = makeFolder("Pinned")
        appState.pinItem(folder)

        // Simulate what PinnedItemRow.handleTap() does
        appState.expandAndScrollToFolder(folder)

        XCTAssertEqual(appState.focusPinnedFolder, folder)
    }

    func test_multipleExpandCalls_eachSetsCorrectURL() {
        let a = makeFolder("Alpha")
        let b = makeFolder("Beta")
        let c = makeFolder("Gamma")

        for (folder, expected) in [(a, a), (b, b), (c, c)] {
            appState.focusPinnedFolder = nil
            appState.expandAndScrollToFolder(folder)
            XCTAssertEqual(appState.focusPinnedFolder, expected)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFolder(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
