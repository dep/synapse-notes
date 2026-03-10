import XCTest
@testable import Noted

/// Tests for AppState.refreshAllFiles() — the method that populates allFiles (markdown only)
/// and allProjectFiles (all files). These arrays drive the command palette, the wiki-link
/// graph, and the file-tree badge count, so their correctness is critical.
final class AppStateRefreshAllFilesTests: XCTestCase {

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

    // MARK: - Helpers

    @discardableResult
    private func createFile(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func createSubdirectory(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - No workspace

    func test_noRootURL_allFilesIsEmpty() {
        sut.rootURL = nil
        sut.refreshAllFiles()
        XCTAssertTrue(sut.allFiles.isEmpty)
    }

    func test_noRootURL_allProjectFilesIsEmpty() {
        sut.rootURL = nil
        sut.refreshAllFiles()
        XCTAssertTrue(sut.allProjectFiles.isEmpty)
    }

    // MARK: - Markdown file discovery (allFiles)

    func test_mdFile_appearsInAllFiles() {
        createFile(named: "note.md")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "note.md" })
    }

    func test_markdownFile_appearsInAllFiles() {
        createFile(named: "article.markdown")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "article.markdown" })
    }

    func test_mdFileExtensionCaseInsensitive_appearsInAllFiles() {
        // The filter lowercases the extension, so .MD should also be included
        createFile(named: "UPPER.MD")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "UPPER.MD" })
    }

    // MARK: - Non-markdown files excluded from allFiles but in allProjectFiles

    func test_txtFile_notInAllFiles() {
        createFile(named: "readme.txt")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == "readme.txt" })
    }

    func test_txtFile_inAllProjectFiles() {
        createFile(named: "readme.txt")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allProjectFiles.contains { $0.lastPathComponent == "readme.txt" })
    }

    func test_imageFile_notInAllFiles() {
        createFile(named: "photo.png")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == "photo.png" })
    }

    func test_imageFile_inAllProjectFiles() {
        createFile(named: "photo.png")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allProjectFiles.contains { $0.lastPathComponent == "photo.png" })
    }

    func test_swiftFile_notInAllFiles_butInProjectFiles() {
        createFile(named: "AppState.swift")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == "AppState.swift" })
        XCTAssertTrue(sut.allProjectFiles.contains { $0.lastPathComponent == "AppState.swift" })
    }

    // MARK: - Hidden files excluded

    func test_hiddenMdFile_excludedFromAllFiles() {
        createFile(named: ".hidden.md")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == ".hidden.md" })
    }

    func test_hiddenMdFile_excludedFromAllProjectFiles() {
        createFile(named: ".hidden.md")
        sut.openFolder(tempDir)
        XCTAssertFalse(sut.allProjectFiles.contains { $0.lastPathComponent == ".hidden.md" })
    }

    func test_hiddenDirectory_excludedFromDiscovery() {
        let hiddenDir = tempDir.appendingPathComponent(".hidden", isDirectory: true)
        try? FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        let insideHidden = hiddenDir.appendingPathComponent("secret.md")
        try? "".write(to: insideHidden, atomically: true, encoding: .utf8)

        sut.openFolder(tempDir)

        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == "secret.md" })
        XCTAssertFalse(sut.allProjectFiles.contains { $0.lastPathComponent == "secret.md" })
    }

    // MARK: - Nested file discovery

    func test_nestedMdFile_discoveredInAllFiles() {
        let subdir = createSubdirectory(named: "subdir")
        let nestedURL = subdir.appendingPathComponent("deep.md")
        try? "".write(to: nestedURL, atomically: true, encoding: .utf8)

        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "deep.md" })
    }

    func test_deeplyNestedMdFile_discoveredInAllFiles() {
        let level1 = createSubdirectory(named: "level1")
        let level2 = level1.appendingPathComponent("level2", isDirectory: true)
        try? FileManager.default.createDirectory(at: level2, withIntermediateDirectories: true)
        let nested = level2.appendingPathComponent("deepest.md")
        try? "".write(to: nested, atomically: true, encoding: .utf8)

        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "deepest.md" })
    }

    // MARK: - Dynamic updates

    func test_refreshAllFiles_updatesWhenNewFileAdded() {
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.isEmpty, "Should start empty")

        createFile(named: "new.md")
        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "new.md" })
    }

    func test_refreshAllFiles_updatesWhenFileRemoved() throws {
        let url = createFile(named: "temporary.md")
        sut.openFolder(tempDir)
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "temporary.md" })

        try FileManager.default.removeItem(at: url)
        sut.refreshAllFiles()

        XCTAssertFalse(sut.allFiles.contains { $0.lastPathComponent == "temporary.md" })
    }

    // MARK: - Sorting

    func test_allFiles_isSortedAlphabetically() {
        createFile(named: "zebra.md")
        createFile(named: "apple.md")
        createFile(named: "mango.md")
        sut.openFolder(tempDir)

        let names = sut.allFiles.map { $0.lastPathComponent }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    func test_allProjectFiles_isSortedAlphabetically() {
        createFile(named: "zebra.txt")
        createFile(named: "apple.txt")
        sut.openFolder(tempDir)

        let names = sut.allProjectFiles.map { $0.lastPathComponent }
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    // MARK: - Mixed content

    func test_onlyMarkdownCountedInAllFiles() {
        createFile(named: "note.md")
        createFile(named: "readme.txt")
        createFile(named: "photo.png")
        createFile(named: "article.markdown")

        sut.openFolder(tempDir)

        XCTAssertEqual(sut.allFiles.count, 2)
        XCTAssertEqual(sut.allProjectFiles.count, 4)
    }
}
