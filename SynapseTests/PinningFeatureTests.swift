import XCTest
@testable import Synapse

/// Tests for Pinning feature: pinning notes and folders for quick access
final class PinningFeatureTests: XCTestCase {

    var appState: AppState!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        
        // Create temp directory for test vault
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Use a temp config path for testing
        configFilePath = tempDir.appendingPathComponent("test-settings.json").path
        
        // Initialize AppState
        appState = AppState()
        // Replace the default settings with our test settings
        appState.replaceSettingsForTesting(SettingsManager(configPath: configFilePath))
        appState.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        appState = nil
        super.tearDown()
    }

    // MARK: - Basic Pin/Unpin Operations

    func test_pinItem_addsToPinnedList() throws {
        let fileURL = createFile(at: "notes/test.md", contents: "# Test")
        
        appState.pinItem(fileURL)
        
        XCTAssertTrue(appState.isPinned(fileURL), "Item should be pinned")
        XCTAssertEqual(appState.pinnedItems.count, 1)
    }

    func test_unpinItem_removesFromPinnedList() throws {
        let fileURL = createFile(at: "notes/test.md", contents: "# Test")
        appState.pinItem(fileURL)
        
        appState.unpinItem(fileURL)
        
        XCTAssertFalse(appState.isPinned(fileURL), "Item should not be pinned after unpinning")
        XCTAssertEqual(appState.pinnedItems.count, 0)
    }

    func test_pinFolder_addsToPinnedList() throws {
        let folderURL = createFolder(at: "projects")
        
        appState.pinItem(folderURL)
        
        XCTAssertTrue(appState.isPinned(folderURL), "Folder should be pinned")
        XCTAssertEqual(appState.pinnedItems.count, 1)
    }

    func test_unpinFolder_removesFromPinnedList() throws {
        let folderURL = createFolder(at: "projects")
        appState.pinItem(folderURL)
        
        appState.unpinItem(folderURL)
        
        XCTAssertFalse(appState.isPinned(folderURL), "Folder should not be pinned after unpinning")
    }

    // MARK: - Multiple Items

    func test_pinMultipleItems_maintainsOrder() throws {
        let file1 = createFile(at: "a.md", contents: "A")
        let file2 = createFile(at: "b.md", contents: "B")
        let folder = createFolder(at: "folder")
        
        appState.pinItem(file1)
        appState.pinItem(file2)
        appState.pinItem(folder)
        
        XCTAssertEqual(appState.pinnedItems.count, 3)
        XCTAssertEqual(appState.pinnedItems[0].url, file1)
        XCTAssertEqual(appState.pinnedItems[1].url, file2)
        XCTAssertEqual(appState.pinnedItems[2].url, folder)
    }

    func test_pinSameItemTwice_doesNotDuplicate() throws {
        let fileURL = createFile(at: "notes/test.md", contents: "# Test")
        
        appState.pinItem(fileURL)
        appState.pinItem(fileURL)
        
        XCTAssertEqual(appState.pinnedItems.count, 1, "Should not duplicate pinned items")
    }

    // MARK: - Persistence

    func test_pinnedItems_persistToDisk() throws {
        let fileURL = createFile(at: "notes/persist.md", contents: "# Persist")
        let folderURL = createFolder(at: "persist-folder")
        
        appState.pinItem(fileURL)
        appState.pinItem(folderURL)
        
        // Create new AppState instance with same config
        let newAppState = AppState()
        newAppState.replaceSettingsForTesting(SettingsManager(configPath: configFilePath))
        newAppState.openFolder(tempDir)
        
        XCTAssertTrue(newAppState.isPinned(fileURL), "Pinned file should persist")
        XCTAssertTrue(newAppState.isPinned(folderURL), "Pinned folder should persist")
        XCTAssertEqual(newAppState.pinnedItems.count, 2)
    }

    // MARK: - Missing File Cleanup

    func test_pinnedItemWithMissingFile_isSilentlyRemoved() throws {
        let fileURL = createFile(at: "temp/temp.md", contents: "# Temp")
        appState.pinItem(fileURL)
        
        // Delete the file
        try FileManager.default.removeItem(at: fileURL)
        
        // Re-initialize AppState (simulates app restart)
        let newAppState = AppState()
        newAppState.replaceSettingsForTesting(SettingsManager(configPath: configFilePath))
        newAppState.openFolder(tempDir)
        
        XCTAssertEqual(newAppState.pinnedItems.count, 0, "Missing file should be removed from pins")
    }

    func test_pinnedFolderWithMissingFolder_isSilentlyRemoved() throws {
        let folderURL = createFolder(at: "temp-folder")
        appState.pinItem(folderURL)
        
        // Delete the folder
        try FileManager.default.removeItem(at: folderURL)
        
        // Re-initialize AppState
        let newAppState = AppState()
        newAppState.replaceSettingsForTesting(SettingsManager(configPath: configFilePath))
        newAppState.openFolder(tempDir)
        
        XCTAssertEqual(newAppState.pinnedItems.count, 0, "Missing folder should be removed from pins")
    }

    func test_pinnedItemsWithSomeMissing_keepsValidOnes() throws {
        let file1 = createFile(at: "keep.md", contents: "Keep")
        let file2 = createFile(at: "remove.md", contents: "Remove")
        appState.pinItem(file1)
        appState.pinItem(file2)
        
        // Delete only file2
        try FileManager.default.removeItem(at: file2)
        
        // Re-initialize
        let newAppState = AppState()
        newAppState.replaceSettingsForTesting(SettingsManager(configPath: configFilePath))
        newAppState.openFolder(tempDir)
        
        XCTAssertEqual(newAppState.pinnedItems.count, 1)
        XCTAssertTrue(newAppState.isPinned(file1))
        XCTAssertFalse(newAppState.isPinned(file2))
    }

    // MARK: - Vault-Specific Pins

    func test_pinsAreVaultSpecific() throws {
        let fileURL = createFile(at: "vault1-file.md", contents: "V1")
        appState.pinItem(fileURL)
        
        // Create different vault
        let otherVault = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: otherVault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherVault) }
        
        // Create file with same name in other vault
        let otherFile = otherVault.appendingPathComponent("vault1-file.md")
        try "Other".write(to: otherFile, atomically: true, encoding: .utf8)
        
        // Open other vault
        appState.openFolder(otherVault)
        
        // Pin from other vault should not be present
        XCTAssertEqual(appState.pinnedItems.count, 0, "Pins should be vault-specific")
    }

    // MARK: - Pinned Item Metadata

    func test_pinnedItem_hasCorrectMetadata() throws {
        let fileURL = createFile(at: "notes/meta.md", contents: "# Meta")
        let folderURL = createFolder(at: "meta-folder")
        
        appState.pinItem(fileURL)
        appState.pinItem(folderURL)
        
        let filePin = appState.pinnedItems.first { $0.url == fileURL }
        let folderPin = appState.pinnedItems.first { $0.url == folderURL }
        
        XCTAssertNotNil(filePin)
        XCTAssertNotNil(folderPin)
        XCTAssertFalse(filePin!.isFolder)
        XCTAssertTrue(folderPin!.isFolder)
        XCTAssertEqual(filePin!.name, "meta.md")
        XCTAssertEqual(folderPin!.name, "meta-folder")
    }

    // MARK: - Helpers

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func createFolder(at relativePath: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
