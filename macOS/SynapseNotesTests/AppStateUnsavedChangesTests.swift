import XCTest
@testable import Synapse

/// Tests for AppState multi-pane unsaved-changes management.
///
/// `hasUnsavedChanges()` must accurately report whether ANY open pane holds
/// edits that haven't been written to disk.  `saveAllUnsavedChanges()` must
/// flush every dirty pane so no data is lost when the app quits or the user
/// switches vaults.  Neither method was previously covered by the test suite.
final class AppStateUnsavedChangesTests: XCTestCase {

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

    // MARK: - hasUnsavedChanges — single pane

    func test_hasUnsavedChanges_withNoDirtyPanes_returnsFalse() {
        sut.openFile(fileA)
        XCTAssertFalse(sut.isDirty)
        XCTAssertFalse(sut.hasUnsavedChanges())
    }

    func test_hasUnsavedChanges_whenActivePaneIsDirty_returnsTrue() {
        sut.openFile(fileA)
        sut.isDirty = true

        XCTAssertTrue(sut.hasUnsavedChanges())
    }

    func test_hasUnsavedChanges_afterSave_returnsFalse() {
        sut.openFile(fileA)
        sut.isDirty = true

        sut.saveCurrentFile(content: sut.fileContent)

        XCTAssertFalse(sut.hasUnsavedChanges())
    }

    // MARK: - hasUnsavedChanges — split pane

    func test_hasUnsavedChanges_withDirtyInactivePaneOnly_returnsTrue() {
        sut.openFile(fileA)         // pane 0 opens fileA
        sut.splitVertically()       // pane 1 created (copy of pane 0)
        sut.openFile(fileB)         // pane 1 opens fileB
        sut.isDirty = true          // mark pane 1 as dirty

        sut.activePaneIndex = 0     // switch to pane 0 (pane 1 state is snapshotted)

        // Active pane (0) is clean, but inactive pane (1) has unsaved changes.
        XCTAssertFalse(sut.isDirty, "Active pane should not be dirty")
        XCTAssertTrue(sut.hasUnsavedChanges(), "Should detect dirty state in inactive pane")
    }

    func test_hasUnsavedChanges_withBothPanesDirty_returnsTrue() {
        sut.openFile(fileA)
        sut.isDirty = true
        sut.splitVertically()
        sut.openFile(fileB)
        sut.isDirty = true

        XCTAssertTrue(sut.hasUnsavedChanges())
    }

    func test_hasUnsavedChanges_afterClosingDirtyPane_returnsFalse() {
        sut.openFile(fileA)
        sut.splitVertically()
        sut.openFile(fileB)

        // Close pane 1 (no dirty state)
        sut.closePane(1)

        XCTAssertFalse(sut.hasUnsavedChanges())
    }

    // MARK: - saveAllUnsavedChanges — single pane

    func test_saveAllUnsavedChanges_withDirtyActivePane_writesToDisk() throws {
        sut.openFile(fileA)
        sut.fileContent = "Updated content"
        sut.isDirty = true

        sut.saveAllUnsavedChanges()

        let onDisk = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(onDisk, "Updated content")
    }

    func test_saveAllUnsavedChanges_clearsDirtyFlag() {
        sut.openFile(fileA)
        sut.isDirty = true

        sut.saveAllUnsavedChanges()

        XCTAssertFalse(sut.isDirty)
    }

    func test_saveAllUnsavedChanges_whenNotDirty_doesNothing() throws {
        sut.openFile(fileA)
        let original = try String(contentsOf: fileA, encoding: .utf8)
        sut.isDirty = false

        sut.saveAllUnsavedChanges()

        let afterSave = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(afterSave, original, "Non-dirty file should not be rewritten")
    }

    // MARK: - saveAllUnsavedChanges — split pane inactive pane

    func test_saveAllUnsavedChanges_savesInactivePaneToDisk() throws {
        // Open fileB in pane 1, mark it dirty, then switch away.
        sut.openFile(fileA)
        sut.splitVertically()
        sut.openFile(fileB)
        sut.fileContent = "Modified B content"
        sut.isDirty = true

        // Switch to pane 0 — pane 1 state is now "inactive".
        sut.activePaneIndex = 0

        sut.saveAllUnsavedChanges()

        let onDisk = try String(contentsOf: fileB, encoding: .utf8)
        XCTAssertEqual(onDisk, "Modified B content",
                       "Inactive pane's dirty content should be written to disk")
    }

    // MARK: - hasUnsavedChanges is consistent with isDirty

    func test_hasUnsavedChanges_withNoOpenFiles_returnsFalse() {
        XCTAssertFalse(sut.hasUnsavedChanges())
    }

    func test_hasUnsavedChanges_reflects_isDirty_changes() {
        sut.openFile(fileA)

        sut.isDirty = false
        XCTAssertFalse(sut.hasUnsavedChanges())

        sut.isDirty = true
        XCTAssertTrue(sut.hasUnsavedChanges())

        sut.isDirty = false
        XCTAssertFalse(sut.hasUnsavedChanges())
    }
}
