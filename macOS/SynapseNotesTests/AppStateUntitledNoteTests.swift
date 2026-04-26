import XCTest
@testable import Synapse

/// Tests for createNewUntitledNote: directory selection, promptForRename, templates-folder avoidance.
final class AppStateUntitledNoteTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    private func makeDir(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(in directory: URL, named name: String) -> URL {
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "".data(using: .utf8))
        return url
    }

    // MARK: - No selected file: vault root

    func test_noSelectedFile_createsNoteInVaultRoot() {
        sut.selectedFile = nil
        sut.createNewUntitledNote()

        XCTAssertNotNil(sut.selectedFile)
        XCTAssertEqual(
            sut.selectedFile?.deletingLastPathComponent().standardized,
            tempDir.standardized,
            "Untitled note should be in vault root when no file is selected"
        )
    }

    // MARK: - Selected file in subdirectory: note goes there

    func test_selectedFileInSubdir_createsNoteInSameDir() {
        let subdir = makeDir(named: "notes")
        let noteInSubdir = makeFile(in: subdir, named: "existing.md")
        sut.openFile(noteInSubdir)

        sut.createNewUntitledNote()

        XCTAssertNotNil(sut.selectedFile)
        XCTAssertEqual(
            sut.selectedFile?.deletingLastPathComponent().standardized,
            subdir.standardized,
            "Untitled note should be placed in the same directory as the selected file"
        )
    }

    // MARK: - Templates folder avoidance

    func test_selectedFileInTemplatesDir_createsNoteInVaultRoot() {
        sut.settings.templatesDirectory = "templates"
        let templatesDir = makeDir(named: "templates")
        let templateFile = makeFile(in: templatesDir, named: "Meeting.md")
        sut.refreshAllFiles()
        sut.openFileInNewTab(templateFile)

        sut.createNewUntitledNote()

        XCTAssertNotNil(sut.selectedFile)
        XCTAssertEqual(
            sut.selectedFile?.deletingLastPathComponent().standardized,
            tempDir.standardized,
            "Untitled note must fall back to vault root, not the templates folder"
        )
    }

    // MARK: - promptForRename

    func test_promptForRenameTrue_setsPendingTemplateRename() {
        sut.createNewUntitledNote(promptForRename: true)

        XCTAssertNotNil(sut.pendingTemplateRename, "pendingTemplateRename should be set when promptForRename is true")
        XCTAssertEqual(sut.pendingTemplateRename?.url, sut.selectedFile)
    }

    func test_promptForRenameFalse_doesNotSetPendingRename() {
        sut.createNewUntitledNote(promptForRename: false)

        XCTAssertNil(sut.pendingTemplateRename, "pendingTemplateRename should remain nil when promptForRename is false")
    }

    // MARK: - Tab and file list

    func test_createsNote_addsToTabs() {
        sut.createNewUntitledNote()

        XCTAssertFalse(sut.tabs.isEmpty, "A new tab should be opened for the untitled note")
        XCTAssertNotNil(sut.activeTabIndex)
    }

    func test_createsNote_appearsInAllFiles() {
        sut.createNewUntitledNote()

        guard let newFile = sut.selectedFile else {
            XCTFail("selectedFile should be set after creating untitled note")
            return
        }
        XCTAssertTrue(sut.allFiles.contains(newFile), "New note should appear in allFiles")
    }

    // MARK: - targetDirectoryForTemplate is cleared

    func test_targetDirectoryForTemplate_isClearedAfterCreate() {
        let customDir = makeDir(named: "custom")
        sut.targetDirectoryForTemplate = customDir

        sut.createNewUntitledNote()

        XCTAssertNil(sut.targetDirectoryForTemplate, "targetDirectoryForTemplate should be cleared after note creation")
    }

    func test_targetDirectoryForTemplate_createsNoteInSpecifiedDir() {
        let customDir = makeDir(named: "custom")
        sut.targetDirectoryForTemplate = customDir

        sut.createNewUntitledNote()

        XCTAssertNotNil(sut.selectedFile)
        XCTAssertEqual(
            sut.selectedFile?.deletingLastPathComponent().standardized,
            customDir.standardized,
            "Note should be created in targetDirectoryForTemplate when set"
        )
    }
}
