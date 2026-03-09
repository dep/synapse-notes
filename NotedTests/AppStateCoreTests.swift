import XCTest
@testable import Noted

/// Tests for core AppState lifecycle: initial state, folder opening, and UI-state flags
/// (command palette, root-note sheet).
final class AppStateCoreTests: XCTestCase {

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

    // MARK: - Initial state

    func test_initialState_noWorkspace() {
        XCTAssertNil(sut.rootURL)
        XCTAssertNil(sut.selectedFile)
        XCTAssertEqual(sut.fileContent, "")
        XCTAssertFalse(sut.isDirty)
        XCTAssertTrue(sut.allFiles.isEmpty)
        XCTAssertTrue(sut.allProjectFiles.isEmpty)
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
        XCTAssertFalse(sut.isCommandPalettePresented)
        XCTAssertFalse(sut.isRootNoteSheetPresented)
    }

    // MARK: - openFolder

    func test_openFolder_setsRootURL() {
        sut.openFolder(tempDir)
        XCTAssertEqual(sut.rootURL, tempDir)
    }

    func test_openFolder_clearsExistingSelection() {
        let file = tempDir.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: file.path, contents: "hello".data(using: .utf8))
        sut.openFolder(tempDir)
        sut.openFile(file)
        XCTAssertNotNil(sut.selectedFile)

        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }

        sut.openFolder(newDir)
        XCTAssertNil(sut.selectedFile)
        XCTAssertEqual(sut.fileContent, "")
        XCTAssertFalse(sut.isDirty)
    }

    func test_openFolder_resetsNavigationHistory() {
        let file = tempDir.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        sut.openFolder(tempDir)
        sut.openFile(file)
        XCTAssertFalse(sut.canGoBack)

        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }

        sut.openFolder(newDir)
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    // MARK: - Command palette

    func test_presentCommandPalette_requiresWorkspace() {
        sut.presentCommandPalette()
        XCTAssertFalse(sut.isCommandPalettePresented, "Must not present without a workspace")
    }

    func test_presentCommandPalette_withWorkspace_presents() {
        sut.openFolder(tempDir)
        sut.presentCommandPalette()
        XCTAssertTrue(sut.isCommandPalettePresented)
    }

    func test_dismissCommandPalette_hides() {
        sut.openFolder(tempDir)
        sut.presentCommandPalette()
        sut.dismissCommandPalette()
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    // MARK: - Root-note sheet

    func test_presentRootNoteSheet_requiresWorkspace() {
        sut.presentRootNoteSheet()
        XCTAssertFalse(sut.isRootNoteSheetPresented, "Must not present without a workspace")
    }

    func test_presentRootNoteSheet_withWorkspace_presents() {
        sut.openFolder(tempDir)
        sut.presentRootNoteSheet()
        XCTAssertTrue(sut.isRootNoteSheetPresented)
    }

    func test_dismissRootNoteSheet_hides() {
        sut.openFolder(tempDir)
        sut.presentRootNoteSheet()
        sut.dismissRootNoteSheet()
        XCTAssertFalse(sut.isRootNoteSheetPresented)
    }
}
