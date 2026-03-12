import XCTest
@testable import Synapse

/// Tests for buildFileTree hidden item filtering: dot-folders visible, .git excluded, dot-files excluded
final class FileTreeHiddenItemsTests: XCTestCase {

    var vaultDir: URL!
    var settingsDir: URL!
    var settings: SettingsManager!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        vaultDir = base.appendingPathComponent("vault", isDirectory: true)
        settingsDir = base.appendingPathComponent("settings", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        settings = SettingsManager(configPath: settingsDir.appendingPathComponent("settings.json").path)
        settings.fileExtensionFilter = "*" // show all file types
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: vaultDir.deletingLastPathComponent())
        settings = nil
        super.tearDown()
    }

    // MARK: - Dot-folders

    func test_buildFileTree_showsDotPrefixedFolders() {
        createDir(".obsidian")
        createDir("notes")

        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.map(\.name)

        XCTAssertTrue(names.contains(".obsidian"), "Dot-prefixed folders should appear in tree")
        XCTAssertTrue(names.contains("notes"))
    }

    func test_buildFileTree_excludesGitFolder() {
        createDir(".git")
        createDir("notes")

        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.map(\.name)

        XCTAssertFalse(names.contains(".git"), ".git folder should be excluded from tree")
        XCTAssertTrue(names.contains("notes"))
    }

    func test_buildFileTree_showsNestedContentInsideDotFolder() {
        createDir(".obsidian")
        createFile(at: ".obsidian/config.json", contents: "{}")

        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let obsidianNode = nodes.first { $0.name == ".obsidian" }

        XCTAssertNotNil(obsidianNode, ".obsidian folder should be present")
        XCTAssertEqual(obsidianNode?.children?.count, 1, "Contents of dot-folder should be listed")
    }

    // MARK: - Dot-files

    func test_buildFileTree_excludesDotFiles() {
        createFile(at: ".DS_Store", contents: "")
        createFile(at: "note.md", contents: "")

        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.map(\.name)

        XCTAssertFalse(names.contains(".DS_Store"), "Dot-files should be excluded")
        XCTAssertTrue(names.contains("note.md"))
    }

    func test_buildFileTree_excludesDotPrefixedFiles() {
        createFile(at: ".hidden-note.md", contents: "")
        createFile(at: "visible.md", contents: "")

        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        let names = nodes.map(\.name)

        XCTAssertFalse(names.contains(".hidden-note.md"), "Dot-prefixed files should be excluded")
        XCTAssertTrue(names.contains("visible.md"))
    }

    // MARK: - Empty vault

    func test_buildFileTree_emptyDirectory_returnsEmpty() {
        let nodes = buildFileTree(at: vaultDir, sortCriterion: .name, ascending: true, settings: settings)
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Helpers

    @discardableResult
    private func createDir(_ name: String) -> URL {
        let url = vaultDir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = vaultDir.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
