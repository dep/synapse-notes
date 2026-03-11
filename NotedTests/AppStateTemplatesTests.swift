import XCTest
@testable import Noted

final class AppStateTemplatesTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
        // Ensure templates directory is set to default "templates"
        sut.settings.templatesDirectory = "templates"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func test_presentRootNoteSheet_withoutTemplates_createsUntitledBlankNote() throws {
        sut.presentRootNoteSheet()

        let createdNote = try XCTUnwrap(sut.selectedFile)
        XCTAssertEqual(createdNote.deletingLastPathComponent(), tempDir)
        XCTAssertTrue(createdNote.lastPathComponent.hasPrefix("Untitled-"))
        XCTAssertEqual(createdNote.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: createdNote, encoding: .utf8), "")
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_presentRootNoteSheet_withTemplates_presentsTemplatePickerWithoutCreatingNote() throws {
        createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        sut.presentRootNoteSheet()

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertNil(sut.selectedFile)

        let projectFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertEqual(projectFiles.map(\.lastPathComponent).sorted(), ["templates"])
    }

    func test_availableTemplates_onlyReturnsMarkdownFilesInsideConfiguredTemplatesDirectory() {
        createFile(at: "templates/Meeting.md", contents: "# Meeting")
        createFile(at: "templates/Nested/Retro.md", contents: "# Retro")
        createFile(at: "templates/Notes.txt", contents: "ignore")
        createFile(at: "notes/Elsewhere.md", contents: "ignore")
        sut.refreshAllFiles()

        let templatePaths = sut.availableTemplates()
            .map(sut.relativePath(for:))
            .sorted()

        XCTAssertEqual(templatePaths, ["templates/Meeting.md", "templates/Nested/Retro.md"])
    }

    func test_createNoteFromTemplate_createsPopulatedNoteInSelectedFilesDirectory() throws {
        let current = createFile(at: "notes/Today.md", contents: "current")
        let template = createFile(at: "templates/Meeting.md", contents: "# Agenda")
        sut.refreshAllFiles()
        sut.openFile(current)

        let created = try sut.createNoteFromTemplate(template)

        XCTAssertEqual(sut.relativePath(for: created).components(separatedBy: "/").first, "notes")
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "# Agenda")
        XCTAssertEqual(sut.selectedFile, created)
        XCTAssertEqual(sut.fileContent, "# Agenda")
        XCTAssertEqual(sut.pendingTemplateRename?.url, created)
    }

    func test_dismissCommandPalette_afterTemplateFlowDoesNotCreateNote() {
        createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        sut.presentRootNoteSheet()
        sut.dismissCommandPalette()

        XCTAssertFalse(sut.isCommandPalettePresented)
        XCTAssertNil(sut.selectedFile)
        XCTAssertEqual(sut.availableTemplates().count, 1)
    }

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
