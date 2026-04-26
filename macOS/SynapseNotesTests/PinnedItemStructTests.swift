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
    
    // MARK: - Relative Path Tests
    
    func test_pinnedItem_usesRelativePathForPortability() throws {
        // Create a file in the vault
        let noteURL = tempDir.appendingPathComponent("Projects/my-note.md")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: noteURL, atomically: true, encoding: .utf8)
        
        // Create pinned item
        let item = PinnedItem(url: noteURL, isFolder: false, vaultURL: tempDir)
        
        // Encode to JSON
        let data = try JSONEncoder().encode(item)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // The JSON should contain a relative path, not absolute
        // The relative path should be "Projects/my-note.md"
        // Note: JSONEncoder escapes forward slashes as \/
        XCTAssertTrue(jsonString.contains("Projects") && jsonString.contains("my-note.md"), 
                      "Should store relative path in JSON. Got: \(jsonString)")
        
        // Verify the item's URL is correctly computed from relativePath + vaultPath
        XCTAssertEqual(item.url?.path, noteURL.path, 
                       "URL should be computed from vaultPath + relativePath")
        
        // Verify the relative path is correctly calculated
        XCTAssertTrue(item.url?.path.contains("Projects/my-note.md") ?? false,
                      "URL should contain the relative path")
    }
    
    func test_pinnedItem_folderUsesRelativePathForPortability() throws {
        // Create a folder in the vault
        let folderURL = tempDir.appendingPathComponent("Projects/Work")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        // Create pinned item
        let item = PinnedItem(url: folderURL, isFolder: true, vaultURL: tempDir)
        
        // Encode to JSON
        let data = try JSONEncoder().encode(item)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // The JSON should contain a relative path
        XCTAssertTrue(jsonString.contains("Projects") && jsonString.contains("Work"), 
                      "Should store relative path in JSON. Got: \(jsonString)")
        
        // Verify the item's URL is correctly computed
        XCTAssertEqual(item.url?.path, folderURL.path,
                       "URL should be computed from vaultPath + relativePath")
    }
    
    func test_pinnedItem_decodesWithDifferentVaultPath() throws {
        // Create a file in the original vault location
        let noteURL = tempDir.appendingPathComponent("Projects/my-note.md")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: noteURL, atomically: true, encoding: .utf8)
        
        // Create and encode pinned item
        let item = PinnedItem(url: noteURL, isFolder: false, vaultURL: tempDir)
        let data = try JSONEncoder().encode(item)
        var jsonString = String(data: data, encoding: .utf8)!
        
        // Simulate moving vault to different location by modifying JSON
        let newVaultLocation = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: newVaultLocation, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newVaultLocation.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try "".write(to: newVaultLocation.appendingPathComponent("Projects/my-note.md"), atomically: true, encoding: .utf8)
        
        // Replace vaultPath in JSON (handling escaped JSON paths)
        let escapedOriginalPath = tempDir.path.replacingOccurrences(of: "/", with: "\\/")
        let escapedNewPath = newVaultLocation.path.replacingOccurrences(of: "/", with: "\\/")
        jsonString = jsonString.replacingOccurrences(of: escapedOriginalPath, with: escapedNewPath)
        
        // Decode with new vault path
        let modifiedData = jsonString.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PinnedItem.self, from: modifiedData)
        
        // The URL should now point to the new vault location
        let expectedNewURL = newVaultLocation.appendingPathComponent("Projects/my-note.md")
        XCTAssertEqual(decoded.url?.path, expectedNewURL.path,
                       "Decoded item should have URL pointing to new vault location")
        XCTAssertTrue(decoded.exists, "File should exist at new vault location")
        
        // Cleanup
        try? FileManager.default.removeItem(at: newVaultLocation)
    }

    func test_pinnedItem_decodesVaultPathsArray_usesMatchingExistingVault() throws {
        let alternateVault = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: alternateVault, withIntermediateDirectories: true)

        let noteURL = tempDir.appendingPathComponent("Pages/Weight Log.md")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let json = """
        {
          "id": "159CE250-1812-480B-8695-6937583EDF42",
          "name": "Weight Log.md",
          "isFolder": false,
          "isTag": false,
          "vaultPaths": [
            "\(alternateVault.path)",
            "\(tempDir.path)"
          ],
          "relativePath": "Pages/Weight Log.md"
        }
        """

        let decoded = try JSONDecoder().decode(PinnedItem.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.vaultPaths, [alternateVault.path, tempDir.path])
        XCTAssertEqual(decoded.url?.path, noteURL.path)

        try? FileManager.default.removeItem(at: alternateVault)
    }
}
