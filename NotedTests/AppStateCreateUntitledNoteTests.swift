import XCTest
@testable import Noted

/// Tests for `AppState.createNewUntitledNote()` — the function responsible for
/// creating new blank notes with a timestamped name. Covers directory selection logic,
/// templates-directory avoidance, `targetDirectoryForTemplate` handling, and the
/// `promptForRename` flag.
final class AppStateCreateUntitledNoteTests: XCTestCase {

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

    // MARK: - Helpers

    @discardableResult
    private func createFile(at relativePath: String, contents: String = "") -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Creates a file on disk

    func test_createNewUntitledNote_createsFileOnDisk() {
        sut.createNewUntitledNote()

        guard let created = sut.selectedFile else {
            XCTFail("Expected selectedFile to be set after creating an untitled note")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path),
                      "The created note must exist on disk")
    }

    func test_createNewUntitledNote_fileHasMdExtension() {
        sut.createNewUntitledNote()

        guard let file = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertEqual(file.pathExtension, "md", "Untitled note must have a .md extension")
    }

    func test_createNewUntitledNote_fileNameBeginsWithUntitled() {
        sut.createNewUntitledNote()

        guard let file = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertTrue(
            file.lastPathComponent.hasPrefix("Untitled-"),
            "Untitled note filename should start with 'Untitled-', got: \(file.lastPathComponent)"
        )
    }

    // MARK: - Directory selection

    func test_createNewUntitledNote_noSelectedFile_createsInRootDirectory() {
        // No file is open — should fall back to rootURL
        sut.createNewUntitledNote()

        guard let created = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertEqual(
            created.deletingLastPathComponent().standardizedFileURL,
            tempDir.standardizedFileURL,
            "With no file selected, note should be created in the root directory"
        )
    }

    func test_createNewUntitledNote_withSelectedFileInSubdir_createsInSameDirectory() {
        let subdir = tempDir.appendingPathComponent("subfolder", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let existing = createFile(at: "subfolder/existing.md", contents: "hi")
        sut.refreshAllFiles()
        sut.openFile(existing)

        sut.createNewUntitledNote()

        guard let created = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertEqual(
            created.deletingLastPathComponent().standardizedFileURL,
            subdir.standardizedFileURL,
            "Note should be created in the same directory as the currently selected file"
        )
    }

    // MARK: - Templates directory avoidance

    func test_createNewUntitledNote_whenCurrentFileInTemplatesDir_createsInRootInstead() {
        sut.settings.templatesDirectory = "templates"
        let templateFile = createFile(at: "templates/meeting.md", contents: "# Meeting")
        sut.refreshAllFiles()
        sut.openFile(templateFile)

        sut.createNewUntitledNote()

        guard let created = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertEqual(
            created.deletingLastPathComponent().standardizedFileURL,
            tempDir.standardizedFileURL,
            "Note should fall back to root when the selected file is inside the templates directory"
        )
    }

    // MARK: - promptForRename flag

    func test_createNewUntitledNote_withPromptForRename_setsPendingTemplateRename() {
        sut.createNewUntitledNote(promptForRename: true)

        XCTAssertNotNil(sut.pendingTemplateRename,
                        "pendingTemplateRename should be set when promptForRename is true")
        XCTAssertEqual(
            sut.pendingTemplateRename?.url,
            sut.selectedFile,
            "pendingTemplateRename.url should point to the newly created file"
        )
    }

    func test_createNewUntitledNote_withoutPromptForRename_doesNotSetPendingTemplateRename() {
        sut.createNewUntitledNote(promptForRename: false)

        XCTAssertNil(sut.pendingTemplateRename,
                     "pendingTemplateRename should remain nil when promptForRename is false")
    }

    // MARK: - targetDirectoryForTemplate

    func test_createNewUntitledNote_withTargetDirectory_createsInTargetDirectory() {
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try! FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        sut.targetDirectoryForTemplate = targetDir

        sut.createNewUntitledNote()

        guard let created = sut.selectedFile else {
            XCTFail("Expected a file to be created")
            return
        }
        XCTAssertEqual(
            created.deletingLastPathComponent().standardizedFileURL,
            targetDir.standardizedFileURL,
            "Note should be created inside targetDirectoryForTemplate when set"
        )
    }

    func test_createNewUntitledNote_clearsTargetDirectoryAfterCreating() {
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try! FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        sut.targetDirectoryForTemplate = targetDir

        sut.createNewUntitledNote()

        XCTAssertNil(sut.targetDirectoryForTemplate,
                     "targetDirectoryForTemplate should be cleared after the note is created")
    }

    // MARK: - Opens in a new tab

    func test_createNewUntitledNote_opensNoteInANewTab() {
        let existingFile = createFile(at: "existing.md")
        sut.refreshAllFiles()
        sut.openFile(existingFile)
        let tabCountBefore = sut.tabs.count

        sut.createNewUntitledNote()

        XCTAssertGreaterThan(
            sut.tabs.count, tabCountBefore,
            "Untitled note should open in a new tab, not replace the current one"
        )
    }
}
