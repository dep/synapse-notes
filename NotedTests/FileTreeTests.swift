import XCTest
@testable import Noted

/// Tests for the buildFileTree(at:sortCriterion:ascending:) free function defined in
/// FileTreeView.swift. This function is the sole source of the left-sidebar file tree,
/// so regressions affect every user interaction with the file browser.
final class FileTreeTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func createFile(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }

    @discardableResult
    private func createDirectory(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Empty directory

    func test_emptyDirectory_returnsEmptyArray() {
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - File type filtering

    func test_mdFiles_included() {
        createFile(named: "note.md")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertTrue(nodes.contains { $0.name == "note.md" })
    }

    func test_markdownFiles_included() {
        createFile(named: "article.markdown")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertTrue(nodes.contains { $0.name == "article.markdown" })
    }

    func test_txtFiles_included() {
        createFile(named: "readme.txt")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertTrue(nodes.contains { $0.name == "readme.txt" })
    }

    func test_pngFiles_excluded() {
        createFile(named: "image.png")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertFalse(nodes.contains { $0.name == "image.png" })
    }

    func test_swiftFiles_excluded() {
        createFile(named: "AppState.swift")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertFalse(nodes.contains { $0.name == "AppState.swift" })
    }

    func test_pdfFiles_excluded() {
        createFile(named: "doc.pdf")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertFalse(nodes.contains { $0.name == "doc.pdf" })
    }

    func test_onlyAllowedExtensionsAppear() {
        createFile(named: "keep.md")
        createFile(named: "keep.txt")
        createFile(named: "discard.png")
        createFile(named: "discard.pdf")
        createFile(named: "discard.json")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        let names = Set(nodes.map { $0.name })

        XCTAssertTrue(names.contains("keep.md"))
        XCTAssertTrue(names.contains("keep.txt"))
        XCTAssertFalse(names.contains("discard.png"))
        XCTAssertFalse(names.contains("discard.pdf"))
        XCTAssertFalse(names.contains("discard.json"))
    }

    // MARK: - Hidden files

    func test_hiddenFiles_excluded() {
        createFile(named: ".hidden.md")
        createFile(named: "visible.md")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        let names = nodes.map { $0.name }

        XCTAssertFalse(names.contains(".hidden.md"))
        XCTAssertTrue(names.contains("visible.md"))
    }

    // MARK: - Directory ordering: directories before files

    func test_directoriesSortBeforeFiles_nameAscending() {
        createFile(named: "aardvark.md")
        createDirectory(named: "zfolder")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)

        XCTAssertFalse(nodes.isEmpty)
        XCTAssertTrue(nodes[0].isDirectory, "First node should be the directory 'zfolder'")
        XCTAssertFalse(nodes[1].isDirectory, "Second node should be the file 'aardvark.md'")
    }

    func test_directoriesSortBeforeFiles_nameDescending() {
        createFile(named: "zfile.md")
        createDirectory(named: "afolder")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: false)

        XCTAssertFalse(nodes.isEmpty)
        XCTAssertTrue(nodes[0].isDirectory, "Directory should still come first regardless of sort direction")
    }

    func test_multipleMixedNodes_directoriesAllBeforeFiles() {
        createDirectory(named: "folderB")
        createDirectory(named: "folderA")
        createFile(named: "note2.md")
        createFile(named: "note1.md")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)

        let directories = nodes.filter { $0.isDirectory }
        let files = nodes.filter { !$0.isDirectory }

        XCTAssertEqual(directories.count, 2)
        XCTAssertEqual(files.count, 2)

        // All directories must come before all files
        let lastDirIndex = nodes.lastIndex { $0.isDirectory } ?? -1
        let firstFileIndex = nodes.firstIndex { !$0.isDirectory } ?? Int.max
        XCTAssertLessThan(lastDirIndex, firstFileIndex)
    }

    // MARK: - Sort by name

    func test_sortByNameAscending() {
        createFile(named: "charlie.md")
        createFile(named: "alpha.md")
        createFile(named: "bravo.md")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        let names = nodes.map { $0.name }

        XCTAssertEqual(names, ["alpha.md", "bravo.md", "charlie.md"])
    }

    func test_sortByNameDescending() {
        createFile(named: "charlie.md")
        createFile(named: "alpha.md")
        createFile(named: "bravo.md")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: false)
        let names = nodes.map { $0.name }

        XCTAssertEqual(names, ["charlie.md", "bravo.md", "alpha.md"])
    }

    func test_sortByNameAscending_caseInsensitive() {
        createFile(named: "Zebra.md")
        createFile(named: "apple.md")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        let names = nodes.map { $0.name }

        // Case-insensitive: "apple" < "Zebra"
        XCTAssertEqual(names.first, "apple.md")
        XCTAssertEqual(names.last, "Zebra.md")
    }

    // MARK: - Sort by modification date

    func test_sortByModifiedAscending_olderFilesFirst() throws {
        let olderURL = createFile(named: "older.md")
        let newerURL = createFile(named: "newer.md")

        let olderDate = Date(timeIntervalSince1970: 1_000_000)
        let newerDate = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderURL.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerURL.path)

        let nodes = buildFileTree(at: tempDir, sortCriterion: .modified, ascending: true)
        let names = nodes.map { $0.name }

        XCTAssertEqual(names.first, "older.md")
        XCTAssertEqual(names.last, "newer.md")
    }

    func test_sortByModifiedDescending_newerFilesFirst() throws {
        let olderURL = createFile(named: "older.md")
        let newerURL = createFile(named: "newer.md")

        let olderDate = Date(timeIntervalSince1970: 1_000_000)
        let newerDate = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderURL.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerURL.path)

        let nodes = buildFileTree(at: tempDir, sortCriterion: .modified, ascending: false)
        let names = nodes.map { $0.name }

        XCTAssertEqual(names.first, "newer.md")
        XCTAssertEqual(names.last, "older.md")
    }

    // MARK: - Directory node structure

    func test_emptyDirectory_producesNodeWithEmptyChildren() {
        createDirectory(named: "emptyFolder")

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)

        XCTAssertEqual(nodes.count, 1)
        let folderNode = nodes[0]
        XCTAssertTrue(folderNode.isDirectory)
        XCTAssertNotNil(folderNode.children)
        XCTAssertTrue(folderNode.children!.isEmpty)
    }

    func test_directoryWithMdChild_producesNodeWithOneChild() {
        let dir = createDirectory(named: "parent")
        let childURL = dir.appendingPathComponent("child.md")
        FileManager.default.createFile(atPath: childURL.path, contents: nil)

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isDirectory)
        XCTAssertEqual(nodes[0].children?.count, 1)
        XCTAssertEqual(nodes[0].children?.first?.name, "child.md")
    }

    func test_directoryWithOnlyNonAllowedFiles_producesNodeWithEmptyChildren() {
        let dir = createDirectory(named: "imgFolder")
        let imgURL = dir.appendingPathComponent("photo.png")
        FileManager.default.createFile(atPath: imgURL.path, contents: nil)

        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isDirectory)
        XCTAssertTrue(nodes[0].children?.isEmpty ?? false)
    }

    // MARK: - FileNode.isMarkdown

    func test_fileNode_isMarkdown_forMdExtension() {
        createFile(named: "note.md")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isMarkdown)
    }

    func test_fileNode_isMarkdown_forMarkdownExtension() {
        createFile(named: "note.markdown")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isMarkdown)
    }

    func test_fileNode_isNotMarkdown_forTxtExtension() {
        createFile(named: "readme.txt")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertFalse(nodes[0].isMarkdown)
    }

    func test_directoryNode_isDirectory() {
        createDirectory(named: "folder")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isDirectory)
    }

    func test_fileNode_isNotDirectory() {
        createFile(named: "note.md")
        let nodes = buildFileTree(at: tempDir, sortCriterion: .name, ascending: true)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertFalse(nodes[0].isDirectory)
    }
}
