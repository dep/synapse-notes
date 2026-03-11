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

    private func makeFile(in directory: URL, named name: String, content: String) -> URL {
        let url = directory.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
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

    func test_openFolder_whenDirty_savesCurrentFileBeforeSwitchingWorkspace() throws {
        let file = makeFile(in: tempDir, named: "dirty.md", content: "before")
        sut.openFolder(tempDir)
        sut.openFile(file)
        sut.fileContent = "after edit"
        sut.isDirty = true

        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }

        sut.openFolder(newDir)

        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(saved, "after edit")
        XCTAssertFalse(sut.isDirty)
    }

    func test_exitVault_whenDirty_savesCurrentFileBeforeClearingState() throws {
        let file = makeFile(in: tempDir, named: "exit.md", content: "before")
        sut.openFolder(tempDir)
        sut.openFile(file)
        sut.fileContent = "after edit"
        sut.isDirty = true

        sut.exitVault()

        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(saved, "after edit")
        XCTAssertNil(sut.rootURL)
        XCTAssertNil(sut.selectedFile)
        XCTAssertFalse(sut.isDirty)
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

    // MARK: - New note workflow

    func test_presentRootNoteSheet_requiresWorkspace() {
        sut.presentRootNoteSheet()
        XCTAssertFalse(sut.isCommandPalettePresented, "Must not present without a workspace")
        XCTAssertNil(sut.selectedFile)
    }

    func test_presentRootNoteSheet_withWorkspaceAndNoTemplates_createsUntitledNote() {
        sut.openFolder(tempDir)
        sut.presentRootNoteSheet()
        XCTAssertNotNil(sut.selectedFile)
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_presentRootNoteSheet_withTemplates_presentsCommandPalette() {
        sut.openFolder(tempDir)
        sut.settings.templatesDirectory = "templates"
        let templatesDirectory = tempDir.appendingPathComponent("templates", isDirectory: true)
        try! FileManager.default.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        let template = templatesDirectory.appendingPathComponent("Meeting.md")
        FileManager.default.createFile(atPath: template.path, contents: "# Meeting".data(using: .utf8))
        sut.refreshAllFiles()

        sut.presentRootNoteSheet()

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertNil(sut.selectedFile)
    }

    func test_dismissRootNoteSheet_hides() {
        sut.openFolder(tempDir)
        sut.isRootNoteSheetPresented = true
        sut.dismissRootNoteSheet()
        XCTAssertFalse(sut.isRootNoteSheetPresented)
    }
}
