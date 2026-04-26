import XCTest
@testable import Synapse

/// Tests for the template rename flow:
///   - `confirmTemplateRename(_:)` — renames the pending note and clears the request
///   - `dismissTemplateRenamePrompt()` — cancels the rename without touching the file
///
/// This flow runs every time a user creates a note from a template: the note is
/// created with a timestamped name, then immediately offered for rename. Breakage
/// here leaves users with `Untitled-2026-…` filenames they cannot easily change.
final class AppStateTemplateRenameTests: XCTestCase {

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

    /// Creates a real file on disk and sets it as the pending template rename target.
    @discardableResult
    private func makePendingNote(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "# Template content".data(using: .utf8))
        sut.pendingTemplateRename = TemplateRenameRequest(url: url)
        return url
    }

    // MARK: - dismissTemplateRenamePrompt

    func test_dismissTemplateRenamePrompt_clearsPendingRename() {
        makePendingNote(named: "Untitled-2026-01-01-120000.md")
        XCTAssertNotNil(sut.pendingTemplateRename)

        sut.dismissTemplateRenamePrompt()

        XCTAssertNil(sut.pendingTemplateRename)
    }

    func test_dismissTemplateRenamePrompt_whenNoPendingRename_doesNotCrash() {
        XCTAssertNil(sut.pendingTemplateRename)
        sut.dismissTemplateRenamePrompt() // should not crash
        XCTAssertNil(sut.pendingTemplateRename)
    }

    func test_dismissTemplateRenamePrompt_doesNotRenameFile() throws {
        let originalURL = makePendingNote(named: "Untitled-original.md")

        sut.dismissTemplateRenamePrompt()

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path),
                      "Original file should still exist after dismissal")
    }

    // MARK: - confirmTemplateRename - success paths

    func test_confirmTemplateRename_renamesFileOnDisk() throws {
        let originalURL = makePendingNote(named: "Untitled-2026-01-01-120000.md")

        try sut.confirmTemplateRename("Meeting Notes")

        let renamedURL = tempDir.appendingPathComponent("Meeting Notes.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path),
                       "Original file should no longer exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path),
                      "Renamed file should exist on disk")
    }

    func test_confirmTemplateRename_clearsPendingRenameAfterSuccess() throws {
        makePendingNote(named: "Untitled-2026.md")

        try sut.confirmTemplateRename("My New Note")

        XCTAssertNil(sut.pendingTemplateRename,
                     "pendingTemplateRename should be nil after successful confirmation")
    }

    func test_confirmTemplateRename_preservesFileContent() throws {
        let originalURL = tempDir.appendingPathComponent("Untitled-temp.md")
        try "# Important Content".write(to: originalURL, atomically: true, encoding: .utf8)
        sut.pendingTemplateRename = TemplateRenameRequest(url: originalURL)

        try sut.confirmTemplateRename("Important Note")

        let renamedURL = tempDir.appendingPathComponent("Important Note.md")
        let content = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertEqual(content, "# Important Content")
    }

    func test_confirmTemplateRename_addsExtensionWhenMissing() throws {
        makePendingNote(named: "Untitled-noext.md")

        try sut.confirmTemplateRename("NoteWithoutExtension")

        let renamedURL = tempDir.appendingPathComponent("NoteWithoutExtension.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path),
                      ".md extension should be preserved when renaming")
    }

    // MARK: - confirmTemplateRename - guard conditions

    func test_confirmTemplateRename_withNoPendingRename_doesNothing() throws {
        XCTAssertNil(sut.pendingTemplateRename)

        try sut.confirmTemplateRename("Anything")
        // Should not throw or crash; nothing to rename
    }

    func test_confirmTemplateRename_invalidEmptyName_throws() {
        makePendingNote(named: "Untitled-empty.md")

        XCTAssertThrowsError(try sut.confirmTemplateRename("")) { error in
            guard let browserError = error as? FileBrowserError,
                  case .invalidName = browserError else {
                XCTFail("Expected FileBrowserError.invalidName, got \(error)")
                return
            }
        }
    }

    func test_confirmTemplateRename_invalidNameWithOnlySlashes_throws() {
        makePendingNote(named: "Untitled-slash.md")

        XCTAssertThrowsError(try sut.confirmTemplateRename("   ")) { error in
            guard let browserError = error as? FileBrowserError,
                  case .invalidName = browserError else {
                XCTFail("Expected FileBrowserError.invalidName, got \(error)")
                return
            }
        }
    }

    func test_confirmTemplateRename_collidingName_throws() throws {
        // Create a file that will collide with the rename destination
        let collidingURL = tempDir.appendingPathComponent("Existing Note.md")
        try "existing".write(to: collidingURL, atomically: true, encoding: .utf8)
        makePendingNote(named: "Untitled-collision.md")

        XCTAssertThrowsError(try sut.confirmTemplateRename("Existing Note")) { error in
            guard let browserError = error as? FileBrowserError,
                  case .itemAlreadyExists = browserError else {
                XCTFail("Expected FileBrowserError.itemAlreadyExists, got \(error)")
                return
            }
        }
    }

    func test_confirmTemplateRename_collidingName_doesNotClearPendingRename() throws {
        let collidingURL = tempDir.appendingPathComponent("Taken.md")
        try "existing".write(to: collidingURL, atomically: true, encoding: .utf8)
        makePendingNote(named: "Untitled-kept.md")

        try? sut.confirmTemplateRename("Taken")

        XCTAssertNotNil(sut.pendingTemplateRename,
                        "pendingTemplateRename should remain set when rename fails")
    }

    // MARK: - Round-trip via createNoteFromTemplate → confirmTemplateRename

    func test_fullTemplateRenameFlow_createsAndRenamesCorrectly() throws {
        // Set up a template
        let templatesDir = tempDir.appendingPathComponent("templates", isDirectory: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        let templateFile = templatesDir.appendingPathComponent("Meeting.md")
        try "# {{date}} Meeting".write(to: templateFile, atomically: true, encoding: .utf8)
        sut.settings.templatesDirectory = "templates"
        sut.refreshAllFiles()

        // Create note from template (sets pendingTemplateRename)
        try sut.createNoteFromTemplate(templateFile)
        XCTAssertNotNil(sut.pendingTemplateRename)

        let pendingURL = sut.pendingTemplateRename!.url

        // Confirm the rename
        try sut.confirmTemplateRename("Weekly Sync")

        XCTAssertNil(sut.pendingTemplateRename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))
        let renamedURL = pendingURL.deletingLastPathComponent().appendingPathComponent("Weekly Sync.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
    }
}
