import XCTest
@testable import Synapse

final class AppStateNewNoteFlowTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    static let fixedDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 12; c.hour = 9; c.minute = 45
        return Calendar.current.date(from: c)!
    }()

    override func setUp() {
        super.setUp()
        sut = AppState(now: { Self.fixedDate })
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
        sut.settings.templatesDirectory = "templates"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - presentRootNoteSheet

    func test_presentRootNoteSheet_withoutTemplates_requestsNamePrompt() {
        sut.presentRootNoteSheet()

        XCTAssertTrue(sut.isNewNotePromptRequested)
        XCTAssertFalse(sut.isCommandPalettePresented)
        XCTAssertNil(sut.selectedFile)
    }

    func test_presentRootNoteSheet_withTemplates_showsTemplatePickerNotNamePrompt() {
        createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        sut.presentRootNoteSheet()

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertEqual(sut.commandPaletteMode, .templates)
        XCTAssertFalse(sut.isNewNotePromptRequested)
        XCTAssertNil(sut.selectedFile)
    }

    func test_presentRootNoteSheet_withDirectory_setsTargetDirectory() {
        let subdir = tempDir.appendingPathComponent("notes", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        sut.presentRootNoteSheet(in: subdir)

        XCTAssertEqual(sut.targetDirectoryForTemplate, subdir)
    }

    func test_presentRootNoteSheet_withDirectoryAndTemplates_setsTargetDirectoryAndShowsPicker() {
        let subdir = tempDir.appendingPathComponent("notes", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        sut.presentRootNoteSheet(in: subdir)

        XCTAssertEqual(sut.targetDirectoryForTemplate, subdir)
        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertFalse(sut.isNewNotePromptRequested)
    }

    func test_dismissCommandPalette_clearsPendingTemplateURL() {
        sut.pendingTemplateURL = createFile(at: "templates/Meeting.md", contents: "# Meeting")

        sut.dismissCommandPalette()

        XCTAssertNil(sut.pendingTemplateURL)
    }

    // MARK: - createNamedNoteFromTemplate

    func test_createNamedNoteFromTemplate_createsFileWithGivenName() throws {
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        let url = try sut.createNamedNoteFromTemplate(template, named: "Standup", in: tempDir)

        XCTAssertEqual(url.lastPathComponent, "Standup.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_createNamedNoteFromTemplate_appliesTemplateVariables() throws {
        let template = createFile(at: "templates/Daily.md",
                                  contents: "# {{year}}-{{month}}-{{day}}\n{{hour}}:{{minute}} {{ampm}}")
        sut.refreshAllFiles()

        let url = try sut.createNamedNoteFromTemplate(template, named: "My Note", in: tempDir)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "# 2026-03-12\n09:45 AM")
    }

    func test_createNamedNoteFromTemplate_stripsCursorVariable() throws {
        let template = createFile(at: "templates/Daily.md", contents: "Start\n{{cursor}}\nEnd")
        sut.refreshAllFiles()

        let url = try sut.createNamedNoteFromTemplate(template, named: "My Note", in: tempDir)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.contains("{{cursor}}"))
        XCTAssertTrue(content.contains("Start"))
        XCTAssertTrue(content.contains("End"))
    }

    func test_createNamedNoteFromTemplate_respectsExplicitDirectory() throws {
        let subdir = tempDir.appendingPathComponent("projects", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        let url = try sut.createNamedNoteFromTemplate(template, named: "Sprint", in: subdir)

        XCTAssertEqual(url.deletingLastPathComponent(), subdir)
    }

    func test_createNamedNoteFromTemplate_respectsTargetDirectoryForTemplate() throws {
        let subdir = tempDir.appendingPathComponent("projects", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()
        sut.targetDirectoryForTemplate = subdir

        let url = try sut.createNamedNoteFromTemplate(template, named: "Sprint")

        XCTAssertEqual(url.deletingLastPathComponent(), subdir)
    }

    func test_createNamedNoteFromTemplate_throwsIfFileAlreadyExists() throws {
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting")
        createFile(at: "Standup.md", contents: "existing")
        sut.refreshAllFiles()

        XCTAssertThrowsError(try sut.createNamedNoteFromTemplate(template, named: "Standup", in: tempDir)) { error in
            guard case FileBrowserError.itemAlreadyExists = error else {
                XCTFail("Expected itemAlreadyExists, got \(error)")
                return
            }
        }
    }

    func test_createNamedNoteFromTemplate_opensNoteInNewTab() throws {
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()

        let url = try sut.createNamedNoteFromTemplate(template, named: "Standup", in: tempDir)

        XCTAssertEqual(sut.selectedFile, url)
        XCTAssertTrue(sut.tabs.contains(.file(url)))
    }

    // MARK: - applyTemplateVariables

    func test_applyTemplateVariables_substitutesAllSixVariables() {
        let result = sut.applyTemplateVariables(to: "{{year}}-{{month}}-{{day}} {{hour}}:{{minute}} {{ampm}}")
        XCTAssertEqual(result.content, "2026-03-12 09:45 AM")
    }

    func test_applyTemplateVariables_stripsCursor() {
        let result = sut.applyTemplateVariables(to: "Before{{cursor}}After")
        XCTAssertEqual(result.content, "BeforeAfter")
    }

    func test_applyTemplateVariables_cursorPosition_atStart() {
        let result = sut.applyTemplateVariables(to: "{{cursor}}After")
        XCTAssertEqual(result.cursorPosition, 0)
        XCTAssertEqual(result.content, "After")
    }

    func test_applyTemplateVariables_cursorPosition_inMiddle() {
        let result = sut.applyTemplateVariables(to: "Before\n{{cursor}}\nAfter")
        XCTAssertEqual(result.cursorPosition, 7) // "Before\n".count == 7
        XCTAssertEqual(result.content, "Before\n\nAfter")
    }

    func test_applyTemplateVariables_cursorPosition_noCursor_returnsNil() {
        let result = sut.applyTemplateVariables(to: "No cursor here")
        XCTAssertNil(result.cursorPosition)
    }

    func test_applyTemplateVariables_pmHour() {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1; c.hour = 14; c.minute = 5
        let pm = Calendar.current.date(from: c)!
        let result = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: pm)
        XCTAssertEqual(result.content, "02:05 PM")
    }

    func test_applyTemplateVariables_noon() {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1; c.hour = 12; c.minute = 0
        let noon = Calendar.current.date(from: c)!
        let result = sut.applyTemplateVariables(to: "{{hour}} {{ampm}}", date: noon)
        XCTAssertEqual(result.content, "12 PM")
    }

    func test_applyTemplateVariables_midnight() {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1; c.hour = 0; c.minute = 0
        let midnight = Calendar.current.date(from: c)!
        let result = sut.applyTemplateVariables(to: "{{hour}} {{ampm}}", date: midnight)
        XCTAssertEqual(result.content, "12 AM")
    }

    func test_applyTemplateVariables_noVariables_returnsContentUnchanged() {
        let content = "# Just a heading\nSome body text."
        XCTAssertEqual(sut.applyTemplateVariables(to: content).content, content)
    }

    func test_createNamedNoteFromTemplate_setsPendingCursorPositionWhenCursorPresent() throws {
        let template = createFile(at: "templates/Daily.md", contents: "# Title\n{{cursor}}\nBody")
        sut.refreshAllFiles()

        _ = try sut.createNamedNoteFromTemplate(template, named: "My Note", in: tempDir)

        XCTAssertEqual(sut.pendingCursorPosition, 8) // "# Title\n".count == 8
    }

    func test_createNamedNoteFromTemplate_pendingCursorPositionNilWhenNoCursor() throws {
        let template = createFile(at: "templates/Meeting.md", contents: "# Meeting\nNo cursor here")
        sut.refreshAllFiles()

        _ = try sut.createNamedNoteFromTemplate(template, named: "My Note", in: tempDir)

        XCTAssertNil(sut.pendingCursorPosition)
    }

    // MARK: - Helpers

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
