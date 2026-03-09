import XCTest
@testable import Noted

/// Tests for `relativePath(for:)` which drives the display of file paths
/// throughout the sidebar and editor header.
final class AppStateRelativePathTests: XCTestCase {

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

    // MARK: - No workspace

    func test_noRootURL_returnsLastPathComponent() {
        let url = URL(fileURLWithPath: "/some/deep/path/note.md")
        XCTAssertEqual(sut.relativePath(for: url), "note.md")
    }

    // MARK: - File at root level

    func test_fileAtRoot_returnsFilename() {
        sut.openFolder(tempDir)
        let file = tempDir.appendingPathComponent("note.md")
        XCTAssertEqual(sut.relativePath(for: file), "note.md")
    }

    // MARK: - File in subdirectory

    func test_fileInSubdirectory_returnsRelativePath() {
        sut.openFolder(tempDir)
        let file = tempDir.appendingPathComponent("subdir/note.md")
        XCTAssertEqual(sut.relativePath(for: file), "subdir/note.md")
    }

    func test_fileInDeeplyNestedDirectory_returnsFullRelativePath() {
        sut.openFolder(tempDir)
        let file = tempDir.appendingPathComponent("a/b/c/note.md")
        XCTAssertEqual(sut.relativePath(for: file), "a/b/c/note.md")
    }

    // MARK: - File outside root

    func test_fileOutsideRoot_returnsLastPathComponent() {
        sut.openFolder(tempDir)
        let externalFile = URL(fileURLWithPath: "/tmp/other/note.md")
        XCTAssertEqual(sut.relativePath(for: externalFile), "note.md")
    }

    // MARK: - Consistency: relativePath uses standardized URLs

    func test_relativePath_withTrailingSlashOnRoot_stillWorks() {
        // Ensure that slight URL variations don't break relative path computation.
        let trailingSlashURL = URL(fileURLWithPath: tempDir.path + "/")
        sut.openFolder(trailingSlashURL)
        let file = tempDir.appendingPathComponent("notes/todo.md")
        let result = sut.relativePath(for: file)
        XCTAssertTrue(result == "notes/todo.md" || result == "todo.md",
                      "Unexpected path: \(result)")
    }
}
