import XCTest
@testable import Noted

/// Tests for AppState's internal prepareName(_:defaultExtension:) via its public API.
/// prepareName governs what filenames are written to disk, so edge cases here
/// are security-adjacent — a regression could create unexpected files or break
/// the entire file-creation flow.
final class AppStatePrepareNameTests: XCTestCase {

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

    // MARK: - Whitespace trimming

    func test_leadingWhitespace_trimmedBeforeCreating() throws {
        let url = try sut.createNote(named: "  LeadingSpaces")
        XCTAssertEqual(url.lastPathComponent, "LeadingSpaces.md")
    }

    func test_trailingWhitespace_trimmedBeforeCreating() throws {
        let url = try sut.createNote(named: "TrailingSpaces  ")
        XCTAssertEqual(url.lastPathComponent, "TrailingSpaces.md")
    }

    func test_leadingAndTrailingWhitespace_trimmed() throws {
        let url = try sut.createNote(named: "  SurroundedBySpaces  ")
        XCTAssertEqual(url.lastPathComponent, "SurroundedBySpaces.md")
    }

    func test_internalWhitespace_preserved() throws {
        let url = try sut.createNote(named: "Multiple Words Here")
        XCTAssertEqual(url.lastPathComponent, "Multiple Words Here.md")
    }

    // MARK: - Slash → dash sanitization

    func test_singleSlash_convertedToDash() throws {
        let url = try sut.createNote(named: "a/b")
        XCTAssertEqual(url.lastPathComponent, "a-b.md")
    }

    func test_multipleSlashes_eachConvertedToDash() throws {
        let url = try sut.createNote(named: "a/b/c")
        XCTAssertEqual(url.lastPathComponent, "a-b-c.md")
    }

    func test_allSlashes_becomesAllDashes_validName() throws {
        // "///" → "---" which is a valid name (not ".", "..", or empty)
        let url = try sut.createNote(named: "///")
        XCTAssertEqual(url.lastPathComponent, "---.md")
    }

    func test_whitespaceAndSlashCombined_trimmedAndSanitized() throws {
        let url = try sut.createNote(named: "  path/to/note  ")
        XCTAssertEqual(url.lastPathComponent, "path-to-note.md")
    }

    // MARK: - Extension behaviour with createNote

    func test_nameWithMdExtension_doesNotDoubleExtend() throws {
        let url = try sut.createNote(named: "AlreadyExtended.md")
        XCTAssertEqual(url.lastPathComponent, "AlreadyExtended.md")
        XCTAssertEqual(url.pathExtension, "md")
    }

    func test_nameWithDifferentExtension_noMdAppended() throws {
        // pathExtension is not empty ("txt"), so ".md" is not appended
        let url = try sut.createNote(named: "Report.txt")
        XCTAssertEqual(url.lastPathComponent, "Report.txt")
    }

    func test_nameWithMarkdownExtension_doesNotDoubleExtend() throws {
        let url = try sut.createNote(named: "Article.markdown")
        XCTAssertEqual(url.lastPathComponent, "Article.markdown")
    }

    // MARK: - Folder creation (no defaultExtension)

    func test_folderName_noExtensionAdded() throws {
        let url = try sut.createFolder(named: "PlainFolder")
        XCTAssertEqual(url.lastPathComponent, "PlainFolder")
        XCTAssertTrue(url.pathExtension.isEmpty)
    }

    func test_folderNameWithSlash_sanitizedToDash() throws {
        let url = try sut.createFolder(named: "parent/child")
        XCTAssertEqual(url.lastPathComponent, "parent-child")
    }

    func test_folderNameWithWhitespace_trimmed() throws {
        let url = try sut.createFolder(named: "  MyFolder  ")
        XCTAssertEqual(url.lastPathComponent, "MyFolder")
    }

    // MARK: - renameItem extension preservation

    func test_renameFile_preservesExistingMdExtension() throws {
        let url = try sut.createNote(named: "Original")
        let newURL = try sut.renameItem(at: url, to: "Renamed")
        XCTAssertEqual(newURL.pathExtension, "md")
        XCTAssertEqual(newURL.deletingPathExtension().lastPathComponent, "Renamed")
    }

    func test_renameFile_dotName_throwsInvalidName() throws {
        let url = try sut.createNote(named: "ToRename")
        XCTAssertThrowsError(try sut.renameItem(at: url, to: ".")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_renameFile_dotDotName_throwsInvalidName() throws {
        let url = try sut.createNote(named: "ToRename2")
        XCTAssertThrowsError(try sut.renameItem(at: url, to: "..")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_renameFile_whitespaceTrimmesToDot_throwsInvalidName() throws {
        // "  .  " trims to "." which is invalid
        let url = try sut.createNote(named: "WillTryDot")
        XCTAssertThrowsError(try sut.renameItem(at: url, to: "  .  ")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_renameFolder_noExtensionAdded() throws {
        let folderURL = try sut.createFolder(named: "OldFolderName")
        let newURL = try sut.renameItem(at: folderURL, to: "NewFolderName")
        XCTAssertEqual(newURL.lastPathComponent, "NewFolderName")
        XCTAssertTrue(newURL.pathExtension.isEmpty)
    }
}
