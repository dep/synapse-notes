import XCTest
@testable import Noted

/// Tests for refreshAllFiles() — specifically the split between allProjectFiles
/// (everything on disk) and allFiles (filtered by SettingsManager.shouldShowFile).
/// This is the core of the sidebar's "what files do I show?" logic.
final class AppStateRefreshFilesTests: XCTestCase {

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
    private func createFile(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    // MARK: - allProjectFiles vs allFiles

    func test_allProjectFiles_containsAllFilesRegardlessOfFilter() {
        sut.settings.fileExtensionFilter = "*.md"
        let mdURL = createFile("note.md")
        let swiftURL = createFile("code.swift")

        sut.refreshAllFiles()

        XCTAssertTrue(sut.allProjectFiles.contains(mdURL),
                      "allProjectFiles should include filtered files")
        XCTAssertTrue(sut.allProjectFiles.contains(swiftURL),
                      "allProjectFiles should include non-filtered files too")
    }

    func test_allFiles_onlyContainsFilesMatchingFilter() {
        sut.settings.fileExtensionFilter = "*.md"
        let mdURL = createFile("note.md")
        let swiftURL = createFile("code.swift")

        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.contains(mdURL), "allFiles should contain .md files")
        XCTAssertFalse(sut.allFiles.contains(swiftURL), "allFiles should NOT contain .swift when filter is *.md")
    }

    func test_allFiles_withWildcardFilter_equalsAllProjectFiles() {
        sut.settings.fileExtensionFilter = "*"
        createFile("note.md")
        createFile("code.swift")
        createFile("README.txt")

        sut.refreshAllFiles()

        XCTAssertEqual(sut.allFiles.count, sut.allProjectFiles.count,
                       "With wildcard filter, allFiles should equal allProjectFiles")
    }

    func test_allFiles_withMultipleExtensions_includesAllMatching() {
        sut.settings.fileExtensionFilter = "*.md, *.txt"
        let md = createFile("note.md")
        let txt = createFile("doc.txt")
        let swift = createFile("code.swift")

        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.contains(md), "Should include .md files")
        XCTAssertTrue(sut.allFiles.contains(txt), "Should include .txt files")
        XCTAssertFalse(sut.allFiles.contains(swift), "Should exclude .swift files")
    }

    func test_allFiles_withEmptyFilter_showsAllFiles() {
        sut.settings.fileExtensionFilter = ""
        createFile("note.md")
        createFile("code.swift")

        sut.refreshAllFiles()

        XCTAssertEqual(sut.allFiles.count, sut.allProjectFiles.count,
                       "Empty filter should show all files")
    }

    // MARK: - No workspace

    func test_refreshAllFiles_withNoWorkspace_producesEmptyArrays() {
        sut.rootURL = nil

        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.isEmpty)
        XCTAssertTrue(sut.allProjectFiles.isEmpty)
    }

    // MARK: - Hidden files are excluded

    func test_refreshAllFiles_hiddenFilesAreExcluded() {
        sut.settings.fileExtensionFilter = "*"
        createFile("visible.md")
        // Hidden files (dot-prefixed) should be skipped by .skipsHiddenFiles
        let hiddenURL = tempDir.appendingPathComponent(".hidden")
        FileManager.default.createFile(atPath: hiddenURL.path, contents: Data())

        sut.refreshAllFiles()

        XCTAssertFalse(sut.allProjectFiles.contains { $0.lastPathComponent == ".hidden" },
                       "Hidden dot-files should be excluded from allProjectFiles")
        XCTAssertTrue(sut.allProjectFiles.contains { $0.lastPathComponent == "visible.md" })
    }

    // MARK: - Subdirectory recursion

    func test_refreshAllFiles_filesInSubdirectories_areDiscovered() throws {
        sut.settings.fileExtensionFilter = "*.md"
        let subdir = tempDir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)
        let nestedFile = createFile("subdir/note.md")

        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.contains(nestedFile),
                      "Files inside subdirectories should appear in allFiles when they match the filter")
    }

    func test_refreshAllFiles_subdirFiles_excludedByExtensionFilter() throws {
        sut.settings.fileExtensionFilter = "*.md"
        let subdir = tempDir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)
        let swiftFile = createFile("subdir/code.swift")

        sut.refreshAllFiles()

        XCTAssertFalse(sut.allFiles.contains(swiftFile),
                       "Non-matching files in subdirectories should be excluded from allFiles")
        XCTAssertTrue(sut.allProjectFiles.contains(swiftFile),
                      "allProjectFiles should include all files regardless of extension")
    }

    // MARK: - File count accuracy

    func test_refreshAllFiles_countMatchesActualFiles() {
        sut.settings.fileExtensionFilter = "*.md"
        createFile("a.md")
        createFile("b.md")
        createFile("c.md")
        createFile("d.swift")

        sut.refreshAllFiles()

        XCTAssertEqual(sut.allFiles.count, 3, "Should have exactly 3 .md files")
        XCTAssertEqual(sut.allProjectFiles.count, 4, "allProjectFiles should have all 4 files")
    }
}
