import XCTest
@testable import Synapse

/// Tests for `AppState.openFolder()` data-preservation behaviour.
///
/// When the user opens a different vault while the current file has unsaved
/// edits, `openFolder()` calls `persistDirtyFileIfNeeded()` which must write
/// the dirty content to disk before tearing down the old vault state.  Failing
/// this silently discards the user's work.
///
/// This specific interaction (dirty-file auto-save during a vault switch) was
/// not previously covered by the test suite.  `AppStateSaveTests` covers
/// the single-file navigation path (`openFile` → auto-save), but not the
/// `openFolder` path.
final class AppStateOpenFolderDirtyFileTests: XCTestCase {

    var sut: AppState!
    var vault1: URL!
    var vault2: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vault1 = base.appendingPathComponent("Vault1", isDirectory: true)
        vault2 = base.appendingPathComponent("Vault2", isDirectory: true)

        try! FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: vault1.deletingLastPathComponent())
        sut = nil
        super.tearDown()
    }

    // MARK: - Dirty file is saved when switching vaults

    func test_openFolder_withDirtyFile_savesBeforeSwitching() throws {
        let note = vault1.appendingPathComponent("note.md")
        try "original content".write(to: note, atomically: true, encoding: .utf8)

        sut.openFolder(vault1)
        sut.openFile(note)
        sut.fileContent = "unsaved edit"
        sut.isDirty = true

        // Switching to a new vault should auto-save the dirty file.
        sut.openFolder(vault2)

        let onDisk = try String(contentsOf: note, encoding: .utf8)
        XCTAssertEqual(onDisk, "unsaved edit",
                       "Dirty content must be written to disk when the user opens a different vault")
    }

    func test_openFolder_withCleanFile_doesNotOverwriteDisk() throws {
        let note = vault1.appendingPathComponent("clean.md")
        try "original content".write(to: note, atomically: true, encoding: .utf8)

        sut.openFolder(vault1)
        sut.openFile(note)
        XCTAssertFalse(sut.isDirty, "Precondition: file is not dirty")

        sut.openFolder(vault2)

        let onDisk = try String(contentsOf: note, encoding: .utf8)
        XCTAssertEqual(onDisk, "original content",
                       "A clean file must not be overwritten when switching vaults")
    }

    // MARK: - State reset after openFolder

    func test_openFolder_resetsSelectedFile() {
        let note = vault1.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: note.path, contents: Data())

        sut.openFolder(vault1)
        sut.openFile(note)
        XCTAssertNotNil(sut.selectedFile)

        sut.openFolder(vault2)

        XCTAssertNil(sut.selectedFile,
                     "selectedFile should be cleared after opening a different vault")
    }

    func test_openFolder_resetsFileContent() {
        let note = vault1.appendingPathComponent("note.md")
        try! "hello".write(to: note, atomically: true, encoding: .utf8)

        sut.openFolder(vault1)
        sut.openFile(note)
        XCTAssertFalse(sut.fileContent.isEmpty)

        sut.openFolder(vault2)

        XCTAssertEqual(sut.fileContent, "",
                       "fileContent should be cleared after opening a different vault")
    }

    func test_openFolder_clearsDirtyFlag() {
        let note = vault1.appendingPathComponent("note.md")
        try! "".write(to: note, atomically: true, encoding: .utf8)

        sut.openFolder(vault1)
        sut.openFile(note)
        sut.isDirty = true

        sut.openFolder(vault2)

        XCTAssertFalse(sut.isDirty,
                       "isDirty should be false after opening a new vault")
    }

    func test_openFolder_setsRootURL() {
        sut.openFolder(vault1)
        XCTAssertEqual(sut.rootURL?.standardizedFileURL, vault1.standardizedFileURL)

        sut.openFolder(vault2)
        XCTAssertEqual(sut.rootURL?.standardizedFileURL, vault2.standardizedFileURL)
    }

    func test_openFolder_preservesTabsFromPreviousVault() {
        // openFolder() does NOT clear the tab bar — it only resets selectedFile,
        // fileContent, and history.  Tabs from the previous vault remain until
        // explicitly closed by the user.  This test documents that behaviour.
        let note = vault1.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: note.path, contents: Data())

        sut.openFolder(vault1)
        sut.openFileInNewTab(note)
        XCTAssertEqual(sut.tabs.count, 1, "Precondition: one tab is open")

        sut.openFolder(vault2)

        XCTAssertEqual(sut.tabs.count, 1,
                       "openFolder does not clear the tab bar; stale tabs from the previous vault remain")
        XCTAssertNil(sut.selectedFile,
                     "selectedFile is cleared even though the tab bar is preserved")
    }

    func test_openFolder_resetsNavigationHistory() {
        let note = vault1.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: note.path, contents: Data())

        sut.openFolder(vault1)
        sut.openFile(note)
        XCTAssertFalse(sut.canGoBack, "Precondition: can go back after opening a file? No.")
        // Open second file to build history.
        let note2 = vault1.appendingPathComponent("note2.md")
        FileManager.default.createFile(atPath: note2.path, contents: Data())
        sut.openFile(note2)

        sut.openFolder(vault2)

        XCTAssertFalse(sut.canGoBack,
                       "Navigation history should be cleared when opening a new vault")
        XCTAssertFalse(sut.canGoForward)
    }

    // MARK: - openFolder with no prior vault

    func test_openFolder_withNoPriorVault_setsRootURLWithoutCrashing() {
        XCTAssertNil(sut.rootURL, "Precondition: no vault is open")

        sut.openFolder(vault1)

        XCTAssertEqual(sut.rootURL?.standardizedFileURL, vault1.standardizedFileURL)
    }

    // MARK: - Command palette is dismissed

    func test_openFolder_dismissesCommandPalette() {
        sut.openFolder(vault1)
        sut.isCommandPalettePresented = true

        sut.openFolder(vault2)

        XCTAssertFalse(sut.isCommandPalettePresented,
                       "Command palette should be dismissed when switching vaults")
    }
}
