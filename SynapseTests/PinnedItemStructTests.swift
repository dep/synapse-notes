import XCTest
@testable import Synapse

/// Tests for the PinnedItem struct: initialization, the `exists` property,
/// and Codable round-tripping.
/// PinningFeatureTests covers the AppState-level behaviour (pin/unpin via AppState);
/// this file tests the PinnedItem value type directly.
final class PinnedItemStructTests: XCTestCase {

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

    // MARK: - File initialiser

    func test_fileInit_setsNameFromLastPathComponent() {
        let url = tempDir.appendingPathComponent("my-note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        let item = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)

        XCTAssertEqual(item.name, "my-note.md")
    }

    func test_fileInit_storesURL() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        let item = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)

        XCTAssertEqual(item.url, url)
    }

    func test_fileInit_isFolder_isFalse() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        let item = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)

        XCTAssertFalse(item.isFolder)
    }

    func test_fileInit_isTag_isFalse() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertFalse(PinnedItem(url: url, isFolder: false, vaultURL: tempDir).isTag)
    }

    func test_fileInit_storesVaultPath() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        let item = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)

        XCTAssertEqual(item.vaultPath, tempDir.path)
    }

    // MARK: - Folder initialiser

    func test_folderInit_isFolder_isTrue() {
        let url = tempDir.appendingPathComponent("my-folder")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let item = PinnedItem(url: url, isFolder: true, vaultURL: tempDir)

        XCTAssertTrue(item.isFolder)
    }

    func test_folderInit_setsNameFromLastPathComponent() {
        let url = tempDir.appendingPathComponent("projects")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let item = PinnedItem(url: url, isFolder: true, vaultURL: tempDir)

        XCTAssertEqual(item.name, "projects")
    }

    // MARK: - Tag initialiser

    func test_tagInit_setsName() {
        let item = PinnedItem(tagName: "swift", vaultURL: tempDir)

        XCTAssertEqual(item.name, "swift")
    }

    func test_tagInit_isTag_isTrue() {
        XCTAssertTrue(PinnedItem(tagName: "swift", vaultURL: tempDir).isTag)
    }

    func test_tagInit_isFolder_isFalse() {
        XCTAssertFalse(PinnedItem(tagName: "swift", vaultURL: tempDir).isFolder)
    }

    func test_tagInit_url_isNil() {
        XCTAssertNil(PinnedItem(tagName: "swift", vaultURL: tempDir).url)
    }

    func test_tagInit_storesVaultPath() {
        let item = PinnedItem(tagName: "swift", vaultURL: tempDir)

        XCTAssertEqual(item.vaultPath, tempDir.path)
    }

    // MARK: - exists — files

    func test_exists_existingFile_returnsTrue() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "content".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(PinnedItem(url: url, isFolder: false, vaultURL: tempDir).exists)
    }

    func test_exists_missingFile_returnsFalse() {
        let url = tempDir.appendingPathComponent("does-not-exist.md")

        XCTAssertFalse(
            PinnedItem(url: url, isFolder: false, vaultURL: tempDir).exists,
            "A file that doesn't exist on disk should return exists == false"
        )
    }

    func test_exists_pinnedAsFileButIsDirectory_returnsFalse() {
        let url = tempDir.appendingPathComponent("actually-a-folder")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        XCTAssertFalse(
            PinnedItem(url: url, isFolder: false, vaultURL: tempDir).exists,
            "An item pinned as a file but stored as a directory should not exist"
        )
    }

    // MARK: - exists — folders

    func test_exists_existingFolder_returnsTrue() {
        let url = tempDir.appendingPathComponent("my-folder")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        XCTAssertTrue(PinnedItem(url: url, isFolder: true, vaultURL: tempDir).exists)
    }

    func test_exists_missingFolder_returnsFalse() {
        let url = tempDir.appendingPathComponent("non-existent-folder")

        XCTAssertFalse(
            PinnedItem(url: url, isFolder: true, vaultURL: tempDir).exists,
            "A folder that doesn't exist on disk should return exists == false"
        )
    }

    func test_exists_pinnedAsFolderButIsRegularFile_returnsFalse() {
        let url = tempDir.appendingPathComponent("actually-a-file.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertFalse(
            PinnedItem(url: url, isFolder: true, vaultURL: tempDir).exists,
            "An item pinned as a folder but stored as a file should not exist"
        )
    }

    // MARK: - exists — tags

    func test_exists_tag_alwaysReturnsTrue() {
        XCTAssertTrue(
            PinnedItem(tagName: "any-tag", vaultURL: tempDir).exists,
            "Tags are virtual items and should always report as existing"
        )
    }

    func test_exists_tagWithEmptyName_alwaysReturnsTrue() {
        XCTAssertTrue(
            PinnedItem(tagName: "", vaultURL: tempDir).exists,
            "Even an empty tag name should report as existing"
        )
    }

    // MARK: - Unique IDs

    func test_twoItemsWithSameURL_haveDifferentIDs() {
        let url = tempDir.appendingPathComponent("note.md")
        try! "".write(to: url, atomically: true, encoding: .utf8)

        let item1 = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)
        let item2 = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)

        XCTAssertNotEqual(item1.id, item2.id, "Each PinnedItem should receive a unique UUID")
    }

    // MARK: - Codable round-trip

    func test_filePinnedItem_roundTripsViaJSON() throws {
        let url = tempDir.appendingPathComponent("note.md")
        try "".write(to: url, atomically: true, encoding: .utf8)

        let original = PinnedItem(url: url, isFolder: false, vaultURL: tempDir)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedItem.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func test_folderPinnedItem_roundTripsViaJSON() throws {
        let url = tempDir.appendingPathComponent("my-folder")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let original = PinnedItem(url: url, isFolder: true, vaultURL: tempDir)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedItem.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func test_tagPinnedItem_roundTripsViaJSON() throws {
        let original = PinnedItem(tagName: "swift", vaultURL: tempDir)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedItem.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func test_decodeLegacyPinnedItemWithoutIsTag_defaultsToFalse() throws {
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "url": "file:///tmp/legacy-note.md",
          "name": "legacy-note.md",
          "isFolder": false,
          "vaultPath": "/tmp/vault"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PinnedItem.self, from: legacyJSON)

        XCTAssertEqual(decoded.name, "legacy-note.md")
        XCTAssertFalse(decoded.isFolder)
        XCTAssertFalse(decoded.isTag, "Legacy pinned items should decode as non-tag items")
        XCTAssertEqual(decoded.url?.path, "/tmp/legacy-note.md")
    }
}
