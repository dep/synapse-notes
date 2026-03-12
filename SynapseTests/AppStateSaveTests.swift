import XCTest
@testable import Synapse

/// Tests for file save/load behaviour: saveCurrentFile writes to disk and clears
/// isDirty; openFile loads content correctly and resets dirty state.
final class AppStateSaveTests: XCTestCase {

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

    private func makeFile(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - saveCurrentFile

    func test_saveCurrentFile_writesContentToDisk() throws {
        let url = makeFile(named: "note.md", content: "original")
        sut.openFile(url)

        sut.saveCurrentFile(content: "updated content")

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "updated content")
    }

    func test_saveCurrentFile_clearsDirtyFlag() {
        let url = makeFile(named: "dirty.md")
        sut.openFile(url)
        sut.isDirty = true

        sut.saveCurrentFile(content: "any content")

        XCTAssertFalse(sut.isDirty)
    }

    func test_saveCurrentFile_withNoSelectedFile_doesNotCrash() {
        sut.selectedFile = nil
        // Should be a no-op and not crash
        sut.saveCurrentFile(content: "orphan")
        XCTAssertNil(sut.selectedFile)
    }

    func test_saveCurrentFile_overwritesExistingContent() throws {
        let url = makeFile(named: "overwrite.md", content: "initial text")
        sut.openFile(url)

        sut.saveCurrentFile(content: "completely new text")

        let result = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(result, "completely new text")
    }

    func test_saveCurrentFile_canSaveEmptyContent() throws {
        let url = makeFile(named: "empty.md", content: "was not empty")
        sut.openFile(url)

        sut.saveCurrentFile(content: "")

        let result = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(result, "")
    }

    // MARK: - openFile content loading

    func test_openFile_loadsContentFromDisk() {
        let url = makeFile(named: "loaded.md", content: "hello from disk")

        sut.openFile(url)

        XCTAssertEqual(sut.fileContent, "hello from disk")
    }

    func test_openFile_setsSelectedFile() {
        let url = makeFile(named: "selected.md")

        sut.openFile(url)

        XCTAssertEqual(sut.selectedFile, url)
    }

    func test_openFile_setsDirtyFalse() {
        let url = makeFile(named: "fresh.md", content: "some content")
        sut.isDirty = true

        sut.openFile(url)

        XCTAssertFalse(sut.isDirty)
    }

    func test_openFile_emptyFile_loadsEmptyContent() {
        let url = makeFile(named: "blank.md", content: "")

        sut.openFile(url)

        XCTAssertEqual(sut.fileContent, "")
    }

    func test_openFile_multilineContent_loadsCorrectly() {
        let multiline = "# Title\n\nParagraph one.\n\nParagraph two."
        let url = makeFile(named: "multi.md", content: multiline)

        sut.openFile(url)

        XCTAssertEqual(sut.fileContent, multiline)
    }

    // MARK: - Auto-save on navigate

    func test_openFile_whenDirty_savesCurrentContentBeforeOpeningNewFile() throws {
        let fileA = makeFile(named: "a.md", content: "original A")
        let fileB = makeFile(named: "b.md", content: "content B")

        sut.openFile(fileA)
        sut.fileContent = "modified A"
        sut.isDirty = true

        sut.openFile(fileB)

        let savedA = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(savedA, "modified A", "Dirty content should be saved before navigating away")
    }

    func test_openFile_whenNotDirty_doesNotOverwriteExistingContent() throws {
        let fileA = makeFile(named: "clean_a.md", content: "original A")
        let fileB = makeFile(named: "clean_b.md", content: "content B")

        sut.openFile(fileA)
        sut.isDirty = false

        sut.openFile(fileB)

        let diskContent = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(diskContent, "original A", "Non-dirty content should not be re-saved")
    }
}
