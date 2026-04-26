import XCTest
@testable import Synapse

/// Tests for the auto-save behaviour that fires when `AppState.closeTab(at:)` is called
/// while the active tab holds unsaved changes.
///
/// The close path is: if `isDirty`, call `saveCurrentFile(content: fileContent)` before
/// removing the tab.  Without this guard, closing a tab with pending edits silently
/// discards them — a data-loss bug that is invisible to the user.
///
/// The existing `AppStateTabsTests` coverage focuses on tab index bookkeeping; none of
/// those tests check whether dirty content reaches disk.
final class AppStateCloseTabAutoSaveTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!
    var fileB: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        fileA = tempDir.appendingPathComponent("NoteA.md")
        fileB = tempDir.appendingPathComponent("NoteB.md")
        try! "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        try! "Content B".write(to: fileB, atomically: true, encoding: .utf8)

        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Auto-save on close (active tab)

    func test_closeTab_whenActiveTabIsDirty_savesContentToDisk() throws {
        sut.openFile(fileA)
        sut.fileContent = "Modified A content"
        sut.isDirty = true

        sut.closeTab(at: 0)

        let onDisk = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(onDisk, "Modified A content",
                       "Closing a dirty tab must flush the in-memory content to disk")
    }

    func test_closeTab_whenActiveTabIsDirty_clearsDirtyFlag() {
        sut.openFile(fileA)
        sut.fileContent = "Modified"
        sut.isDirty = true

        sut.closeTab(at: 0)

        XCTAssertFalse(sut.isDirty,
                       "isDirty must be false after closeTab saves and removes the tab")
    }

    func test_closeTab_whenActiveTabIsClean_doesNotOverwriteDiskContent() throws {
        sut.openFile(fileA)
        sut.isDirty = false  // explicitly clean

        sut.closeTab(at: 0)

        let onDisk = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(onDisk, "Content A",
                       "Closing a clean tab must not write modified content to disk")
    }

    // MARK: - Auto-save when closing a non-active tab

    func test_closeNonActiveTab_withActiveTabDirty_savesActiveToDisk() throws {
        // Open two tabs; make tab 0 (active after close of tab 1) dirty.
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        // Now active is tab 1 (fileB). Switch back to tab 0.
        sut.switchTab(to: 0)
        sut.fileContent = "Modified A"
        sut.isDirty = true

        // Close the non-active tab (tab 1 = fileB) while tab 0 is dirty.
        // The close triggers an autosave of the *active* tab (fileA).
        sut.closeTab(at: 1)

        let onDisk = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(onDisk, "Modified A",
                       "Active tab dirty content should be saved even when closing a non-active tab")
    }

    // MARK: - Multiple tabs — correct tab is saved

    func test_closeTab_savesCorrectFile_notSiblingFile() throws {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.switchTab(to: 1)  // active = fileB
        sut.fileContent = "Modified B"
        sut.isDirty = true

        sut.closeTab(at: 1)   // close the active tab (fileB)

        let onDiskA = try String(contentsOf: fileA, encoding: .utf8)
        let onDiskB = try String(contentsOf: fileB, encoding: .utf8)

        XCTAssertEqual(onDiskB, "Modified B",
                       "Closing a dirty active tab must save that tab's content")
        XCTAssertEqual(onDiskA, "Content A",
                       "Closing fileB must not overwrite fileA")
    }

    // MARK: - Closing the last tab

    func test_closeLastTab_whenDirty_savesContentBeforeClearing() throws {
        sut.openFile(fileA)
        sut.fileContent = "Last dirty edit"
        sut.isDirty = true

        sut.closeTab(at: 0)

        let onDisk = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(onDisk, "Last dirty edit",
                       "Closing the last tab while dirty must persist the content")
        XCTAssertTrue(sut.tabs.isEmpty, "No tabs should remain after closing the last one")
        XCTAssertNil(sut.activeTabIndex)
    }

    // MARK: - State after close

    func test_closeActiveTab_withTwoTabs_focusesSiblingTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.switchTab(to: 1)  // active = fileB at index 1

        sut.closeTab(at: 1)

        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_closeActiveTab_contentLoadedFromSibling() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.switchTab(to: 1)

        sut.closeTab(at: 1)

        XCTAssertEqual(sut.fileContent, "Content A",
                       "After closing fileB, the editor should display fileA's content")
    }
}
