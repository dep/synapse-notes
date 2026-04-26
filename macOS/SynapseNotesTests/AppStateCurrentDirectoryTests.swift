import XCTest
@testable import Synapse

/// Tests for `currentSynapseDirectory()` and `expandAndScrollToFolder(_:)`.
///
/// `currentSynapseDirectory()` is the pivot that decides *where* new notes land:
/// it returns the selected file's parent directory, falling back to the vault root,
/// and then to nil.  Any misimplementation silently places new notes in unexpected
/// locations. `expandAndScrollToFolder(_:)` is the minimal entry-point for pinned-
/// folder navigation: it must set `selectedFile` to the folder URL so the sidebar
/// can scroll to it.
final class AppStateCurrentDirectoryTests: XCTestCase {

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

    // MARK: - currentSynapseDirectory() with no vault open

    func test_currentSynapseDirectory_withNoRootURL_returnsNil() {
        XCTAssertNil(sut.rootURL)
        XCTAssertNil(sut.currentSynapseDirectory())
    }

    // MARK: - currentSynapseDirectory() with vault open but no file selected

    func test_currentSynapseDirectory_withRootURL_andNoSelectedFile_returnsRootURL() {
        sut.openFolder(tempDir)
        XCTAssertNil(sut.selectedFile)

        let directory = sut.currentSynapseDirectory()

        XCTAssertEqual(directory?.standardizedFileURL, tempDir.standardizedFileURL,
                       "Should return vault root when no file is selected")
    }

    // MARK: - currentSynapseDirectory() with a file selected in the root

    func test_currentSynapseDirectory_withFileInRoot_returnsRootDirectory() throws {
        sut.openFolder(tempDir)
        let noteURL = tempDir.appendingPathComponent("Note.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)

        let directory = sut.currentSynapseDirectory()

        XCTAssertEqual(directory?.standardizedFileURL, tempDir.standardizedFileURL,
                       "A file at vault root should report root as its directory")
    }

    // MARK: - currentSynapseDirectory() with a file in a subdirectory

    func test_currentSynapseDirectory_withFileInSubdirectory_returnsSubdirectory() throws {
        sut.openFolder(tempDir)
        let subDir = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let noteURL = subDir.appendingPathComponent("ProjectNote.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)

        let directory = sut.currentSynapseDirectory()

        XCTAssertEqual(directory?.standardizedFileURL, subDir.standardizedFileURL,
                       "A file in a subdirectory should report that subdirectory")
    }

    func test_currentSynapseDirectory_withFileInDeeplyNestedDirectory_returnsImmediateParent() throws {
        sut.openFolder(tempDir)
        let deepDir = tempDir
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let noteURL = deepDir.appendingPathComponent("Deep.md")
        try "deep".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)

        let directory = sut.currentSynapseDirectory()

        XCTAssertEqual(directory?.standardizedFileURL, deepDir.standardizedFileURL,
                       "Should return the immediate parent, not the vault root")
    }

    // MARK: - currentSynapseDirectory() reflects the currently selected file

    func test_currentSynapseDirectory_changesWhenSelectedFileChanges() throws {
        sut.openFolder(tempDir)

        let subDir = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let noteInRoot = tempDir.appendingPathComponent("RootNote.md")
        let noteInSub = subDir.appendingPathComponent("SubNote.md")
        try "root".write(to: noteInRoot, atomically: true, encoding: .utf8)
        try "sub".write(to: noteInSub, atomically: true, encoding: .utf8)

        sut.openFile(noteInRoot)
        XCTAssertEqual(sut.currentSynapseDirectory()?.standardizedFileURL, tempDir.standardizedFileURL)

        sut.openFile(noteInSub)
        XCTAssertEqual(sut.currentSynapseDirectory()?.standardizedFileURL, subDir.standardizedFileURL)
    }

    // MARK: - expandAndScrollToFolder

    func test_expandAndScrollToFolder_setsFocusPinnedFolder() {
        sut.openFolder(tempDir)
        let folderURL = tempDir.appendingPathComponent("MyFolder", isDirectory: true)

        sut.expandAndScrollToFolder(folderURL)

        XCTAssertEqual(sut.focusPinnedFolder?.standardizedFileURL, folderURL.standardizedFileURL,
                       "expandAndScrollToFolder should signal focusPinnedFolder")
    }

    func test_expandAndScrollToFolder_doesNotChangeSelectedFile() throws {
        sut.openFolder(tempDir)
        let noteURL = tempDir.appendingPathComponent("Note.md")
        try "content".write(to: noteURL, atomically: true, encoding: .utf8)
        sut.openFile(noteURL)
        XCTAssertEqual(sut.selectedFile, noteURL)

        let folderURL = tempDir.appendingPathComponent("Docs", isDirectory: true)
        sut.expandAndScrollToFolder(folderURL)

        XCTAssertEqual(sut.selectedFile, noteURL,
                       "expandAndScrollToFolder should not change the current file selection")
    }

    func test_expandAndScrollToFolder_withNilRootURL_stillSetsFocusPinnedFolder() {
        XCTAssertNil(sut.rootURL)

        let folderURL = tempDir.appendingPathComponent("AnyFolder", isDirectory: true)
        sut.expandAndScrollToFolder(folderURL)

        XCTAssertEqual(sut.focusPinnedFolder?.standardizedFileURL, folderURL.standardizedFileURL)
    }

    // MARK: - Interaction: new note is created in currentSynapseDirectory()

    func test_createNote_inCurrentDirectory_placesNoteInSelectedFilesParent() throws {
        sut.openFolder(tempDir)
        let subDir = tempDir.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let existingNote = subDir.appendingPathComponent("Existing.md")
        try "".write(to: existingNote, atomically: true, encoding: .utf8)
        sut.openFile(existingNote)

        let newNote = try sut.createNote(named: "NewFromContext", in: sut.currentSynapseDirectory())

        XCTAssertEqual(newNote.deletingLastPathComponent().standardizedFileURL,
                       subDir.standardizedFileURL,
                       "New note should be created in the current file's directory")
    }
}
