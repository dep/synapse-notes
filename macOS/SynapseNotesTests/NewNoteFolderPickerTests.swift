import XCTest
@testable import Synapse

/// Tests for Issue #194: New Note should ask for folder and remember previous folder
final class NewNoteFolderPickerTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var settings: SettingsManager!

    override func setUp() {
        super.setUp()
        settings = makeTestSettings()
        sut = AppState(settings: settings)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    // Helper to create test settings
    private func makeTestSettings() -> SettingsManager {
        let testConfigPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("SynapseTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        return SettingsManager(configPath: testConfigPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - Initial Default Folder

    func test_newNoteSheet_defaultsToVaultRoot_whenNoHistory() {
        // Given: No previous folder history
        XCTAssertNil(settings.lastNoteFolderPath(forVault: tempDir.path))

        // When: Presenting new note sheet
        sut.presentRootNoteSheet()

        // Then: Should default to vault root
        XCTAssertEqual(sut.targetDirectoryForNewNote, tempDir)
    }

    // MARK: - Remember Last Folder

    func test_newNoteSheet_remembersLastFolderUsed() throws {
        // Given: A subfolder exists
        let subfolder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // When: Creating a note in the subfolder
        _ = try sut.createNote(named: "Test", in: subfolder)

        // Then: Last folder should be remembered
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: tempDir.path), subfolder.path)
    }

    func test_newNoteSheet_usesLastFolder_forSubsequentNotes() throws {
        // Given: A subfolder and previous note creation
        let subfolder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        _ = try sut.createNote(named: "First", in: subfolder)

        // When: Presenting new note sheet again
        sut.presentRootNoteSheet()

        // Then: Should default to the last used folder
        XCTAssertEqual(sut.targetDirectoryForNewNote, subfolder)
    }

    // MARK: - Right-Click Context Menu Override

    func test_newNoteSheet_fromRightClick_usesThatFolder() throws {
        // Given: A subfolder
        let subfolder = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // And: Previous history in a different folder
        let otherFolder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        _ = try sut.createNote(named: "Previous", in: otherFolder)

        // When: Right-clicking on a specific folder to create note
        sut.presentRootNoteSheet(in: subfolder)

        // Then: Should pre-select that folder (override last used)
        XCTAssertEqual(sut.targetDirectoryForNewNote, subfolder)

        // But: Should NOT update the remembered folder until note is created
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: tempDir.path), otherFolder.path)
    }

    func test_newNoteSheet_fromRightClick_updatesMemoryOnlyOnSuccess() throws {
        // Given: A subfolder
        let subfolder = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // When: Right-clicking to create note but canceling
        sut.presentRootNoteSheet(in: subfolder)
        sut.dismissRootNoteSheet()

        // Then: Should NOT update the remembered folder
        XCTAssertNil(settings.lastNoteFolderPath(forVault: tempDir.path))
    }

    // MARK: - Per-Vault Memory

    func test_newNoteSheet_memoryIsPerVault() throws {
        // Given: Two different vaults
        let vault1 = tempDir.appendingPathComponent("vault1", isDirectory: true)
        let vault2 = tempDir.appendingPathComponent("vault2", isDirectory: true)
        try FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)

        // And: Different subfolders in each vault
        let folder1 = vault1.appendingPathComponent("notes", isDirectory: true)
        let folder2 = vault2.appendingPathComponent("drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)

        // When: Creating notes in each vault
        sut.openFolder(vault1)
        _ = try sut.createNote(named: "Vault1Note", in: folder1)

        sut.openFolder(vault2)
        _ = try sut.createNote(named: "Vault2Note", in: folder2)

        // Then: Each vault should remember its own folder
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: vault1.path), folder1.path)
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: vault2.path), folder2.path)
    }

    // MARK: - Folder List Population

    func test_newNoteSheet_listsAllFoldersIncludingRoot() throws {
        // Given: Multiple folders exist
        let folder1 = tempDir.appendingPathComponent("projects", isDirectory: true)
        let folder2 = tempDir.appendingPathComponent("daily", isDirectory: true)
        let nested = folder1.appendingPathComponent("subproject", isDirectory: true)
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        // When: Getting available folders for picker
        let folders = sut.availableFoldersForPicker()

        // Then: Should include root and all folders
        XCTAssertTrue(folders.contains(tempDir))
        XCTAssertTrue(folders.contains(folder1))
        XCTAssertTrue(folders.contains(folder2))
        XCTAssertTrue(folders.contains(nested))
    }

    func test_newNoteSheet_folderListExcludesFiles() throws {
        // Given: Mix of files and folders
        let folder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("existing.md")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        // When: Getting available folders for picker
        let folders = sut.availableFoldersForPicker()

        // Then: Should exclude files
        XCTAssertTrue(folders.contains(folder))
        XCTAssertFalse(folders.contains(file))
        XCTAssertTrue(folders.contains(tempDir))
    }

    // MARK: - Cancel Behavior

    func test_newNoteSheet_cancel_doesNotUpdateMemory() throws {
        // Given: Previous note in a folder
        let folder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try sut.createNote(named: "First", in: folder)

        // When: Opening sheet, changing folder, then canceling
        sut.presentRootNoteSheet()
        let newFolder = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        sut.targetDirectoryForNewNote = newFolder
        sut.dismissRootNoteSheet()

        // Then: Memory should NOT have changed
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: tempDir.path), folder.path)
    }

    // MARK: - Create Note with Selected Folder

    func test_createNote_usesSelectedFolder() throws {
        // Given: A subfolder
        let subfolder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // When: Creating note specifying the folder
        let url = try sut.createNote(named: "MyProject", in: subfolder)

        // Then: Note should be in the specified folder
        XCTAssertEqual(url.deletingLastPathComponent(), subfolder)
        XCTAssertEqual(url.lastPathComponent, "MyProject.md")
    }

    func test_createNote_withSelectedFolder_updatesLastUsed() throws {
        // Given: A subfolder
        let subfolder = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // When: Creating note
        _ = try sut.createNote(named: "Test", in: subfolder)

        // Then: Should update last used folder
        XCTAssertEqual(settings.lastNoteFolderPath(forVault: tempDir.path), subfolder.path)
    }

    func test_createNote_withoutFolder_usesDefault() throws {
        // When: Creating note without specifying folder
        let url = try sut.createNote(named: "RootNote")

        // Then: Should be in vault root
        XCTAssertEqual(url.deletingLastPathComponent(), tempDir)
    }
}
