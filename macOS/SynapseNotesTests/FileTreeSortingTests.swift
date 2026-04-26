import XCTest
@testable import Synapse

/// Tests for buildFileTreeLevel sorting: by name (ascending/descending), by modification date,
/// directories-before-files ordering, and FileNode property helpers.
/// The FileTreeHiddenItemsTests covers filtering; this file covers ordering.
final class FileTreeSortingTests: XCTestCase {

    var vaultDir: URL!
    var settings: SettingsManager!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vaultDir = base.appendingPathComponent("vault", isDirectory: true)
        let settingsDir = base.appendingPathComponent("settings", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        settings = SettingsManager(configPath: settingsDir.appendingPathComponent("settings.json").path)
        settings.fileExtensionFilter = "*"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: vaultDir.deletingLastPathComponent())
        settings = nil
        super.tearDown()
    }

    // MARK: - Name sorting (ascending)

    func test_sortByName_ascending_returnsAlphabeticalOrder() {
        createFile(at: "charlie.md")
        createFile(at: "alpha.md")
        createFile(at: "bravo.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertEqual(nodes.map(\.name), ["alpha.md", "bravo.md", "charlie.md"])
    }

    func test_sortByName_ascending_isCaseInsensitive() {
        createFile(at: "Zebra.md")
        createFile(at: "apple.md")
        createFile(at: "Mango.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.map(\.name)

        XCTAssertEqual(names[0], "apple.md", "Case-insensitive sort: 'apple' should come before 'Mango'")
        XCTAssertEqual(names[1], "Mango.md")
        XCTAssertEqual(names[2], "Zebra.md")
    }

    // MARK: - Name sorting (descending)

    func test_sortByName_descending_returnsReverseAlphabeticalOrder() {
        createFile(at: "charlie.md")
        createFile(at: "alpha.md")
        createFile(at: "bravo.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: false, settings: settings)

        XCTAssertEqual(nodes.map(\.name), ["charlie.md", "bravo.md", "alpha.md"])
    }

    func test_sortByName_descendingThenAscending_returnsCorrectOrders() {
        createFile(at: "note-b.md")
        createFile(at: "note-a.md")

        let asc = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let desc = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: false, settings: settings)

        XCTAssertEqual(asc.map(\.name), ["note-a.md", "note-b.md"])
        XCTAssertEqual(desc.map(\.name), ["note-b.md", "note-a.md"])
    }

    // MARK: - Modified date sorting

    func test_sortByModified_ascending_returnsOldestFirst() throws {
        let old = createFile(at: "old.md")
        Thread.sleep(forTimeInterval: 0.1)
        let recent = createFile(at: "recent.md")

        let oldMod = try old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let recentMod = try recent.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let o = oldMod, let r = recentMod, o < r else {
            throw XCTSkip("Modification dates did not differ — skipping timing-sensitive test")
        }

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .modified, ascending: true, settings: settings)

        XCTAssertEqual(nodes.first?.name, "old.md", "Oldest file should appear first in ascending date sort")
        XCTAssertEqual(nodes.last?.name, "recent.md")
    }

    func test_sortByModified_descending_returnsMostRecentFirst() throws {
        let old = createFile(at: "old.md")
        Thread.sleep(forTimeInterval: 0.1)
        let recent = createFile(at: "recent.md")

        let oldMod = try old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let recentMod = try recent.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let o = oldMod, let r = recentMod, o < r else {
            throw XCTSkip("Modification dates did not differ — skipping timing-sensitive test")
        }

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .modified, ascending: false, settings: settings)

        XCTAssertEqual(nodes.first?.name, "recent.md", "Most recent file should appear first in descending date sort")
        XCTAssertEqual(nodes.last?.name, "old.md")
    }

    // MARK: - Directories always appear before files

    func test_directoriesBeforeFiles_inAscendingSort_evenWhenDirNameIsLater() {
        createFile(at: "aaa.md")
        createDir("zzz")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertTrue(nodes[0].isDirectory, "Directory 'zzz' should precede file 'aaa.md' despite later name")
        XCTAssertFalse(nodes[1].isDirectory)
    }

    func test_directoriesBeforeFiles_inDescendingSort() {
        createDir("aaa")
        createFile(at: "zzz.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: false, settings: settings)

        XCTAssertTrue(nodes[0].isDirectory, "Directories should still precede files in descending sort")
        XCTAssertFalse(nodes[1].isDirectory)
    }

    func test_directoriesBeforeFiles_inModifiedSort() {
        createDir("folder")
        createFile(at: "note.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .modified, ascending: true, settings: settings)

        XCTAssertTrue(nodes[0].isDirectory, "Directories should precede files in modified date sort too")
    }

    func test_multipleDirectories_sortedByNameAmongThemselves() {
        createDir("charlie-dir")
        createDir("alpha-dir")
        createDir("bravo-dir")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.filter(\.isDirectory).map(\.name)

        XCTAssertEqual(names, ["alpha-dir", "bravo-dir", "charlie-dir"])
    }

    // MARK: - FileNode property helpers

    func test_fileNode_name_returnsLastPathComponent() {
        createFile(at: "my-note.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertEqual(nodes.first?.name, "my-note.md")
    }

    func test_fileNode_isDirectory_falseForRegularFile() {
        createFile(at: "note.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertFalse(nodes.first?.isDirectory ?? true)
    }

    func test_fileNode_isDirectory_trueForSubdirectory() {
        createDir("subfolder")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertTrue(nodes.first?.isDirectory ?? false)
    }

    func test_fileNode_isMarkdown_trueForMdExtension() {
        createFile(at: "note.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertTrue(nodes.first?.isMarkdown ?? false)
    }

    func test_fileNode_isMarkdown_trueForMarkdownExtension() {
        createFile(at: "note.markdown")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertTrue(nodes.first?.isMarkdown ?? false)
    }

    func test_fileNode_isMarkdown_falseForTxtExtension() {
        createFile(at: "readme.txt")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertFalse(nodes.first?.isMarkdown ?? true)
    }

    func test_fileNode_isMarkdown_falseForSwiftExtension() {
        createFile(at: "code.swift")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertFalse(nodes.first?.isMarkdown ?? true)
    }

    func test_fileNode_children_nilForRegularFile() {
        createFile(at: "note.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertNil(nodes.first?.children)
    }

    func test_fileNode_children_nonNilForDirectory() {
        createDir("subfolder")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)

        XCTAssertNotNil(nodes.first?.children)
    }

    func test_fileNode_children_containsNestedFiles() {
        createDir("sub")
        createFile(at: "sub/child.md")

        let nodes = buildFileTreeLevel(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let subNode = nodes.first { $0.name == "sub" }

        XCTAssertNotNil(subNode)
        // With lazy loading, children are loaded on demand via a second call
        let children = buildFileTreeLevel(at: subNode!.url, sortCriterion: .name, ascending: true, settings: settings)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.name, "child.md")
    }

    // MARK: - Helpers

    @discardableResult
    private func createFile(at relativePath: String, contents: String = "content") -> URL {
        let url = vaultDir.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func createDir(_ name: String) -> URL {
        let url = vaultDir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
