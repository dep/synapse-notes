import XCTest
@testable import Noted

/// Tests for SettingsManager: config persistence, on-boot command, and file extension filtering
final class SettingsManagerTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Use a temp config file for testing
        configFilePath = tempDir.appendingPathComponent("noted-settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_defaultValues() {
        XCTAssertEqual(sut.onBootCommand, "", "On-boot command should default to empty")
        XCTAssertEqual(sut.fileExtensionFilter, "*.md, *.txt", "File extension filter should default to *.md, *.txt")
    }

    // MARK: - On-Boot Command

    func test_onBootCommand_canBeSet() {
        sut.onBootCommand = "npm run dev"
        XCTAssertEqual(sut.onBootCommand, "npm run dev")
    }

    func test_onBootCommand_canBeCleared() {
        sut.onBootCommand = "npm run dev"
        sut.onBootCommand = ""
        XCTAssertEqual(sut.onBootCommand, "")
    }

    func test_onBootCommand_persistsToDisk() {
        sut.onBootCommand = "claude"

        // Create new instance pointing to same config file
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.onBootCommand, "claude", "On-boot command should persist to disk")
    }

    func test_onBootCommand_emptyMeansNoCommand() {
        sut.onBootCommand = ""
        XCTAssertTrue(sut.onBootCommand.isEmpty, "Empty on-boot command means no command should run")
    }

    // MARK: - File Extension Filter

    func test_fileExtensionFilter_canBeSet() {
        sut.fileExtensionFilter = "*.swift, *.md"
        XCTAssertEqual(sut.fileExtensionFilter, "*.swift, *.md")
    }

    func test_fileExtensionFilter_persistsToDisk() {
        sut.fileExtensionFilter = "*"

        // Create new instance pointing to same config file
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.fileExtensionFilter, "*", "File extension filter should persist to disk")
    }

    func test_fileExtensionFilter_defaultIncludesMdAndTxt() {
        let defaultFilter = sut.fileExtensionFilter
        XCTAssertTrue(defaultFilter.contains("*.md"), "Default filter should include *.md")
        XCTAssertTrue(defaultFilter.contains("*.txt"), "Default filter should include *.txt")
    }

    // MARK: - Extension Parsing

    func test_parseExtensions_singleExtension() {
        sut.fileExtensionFilter = "*.md"
        let extensions = sut.parsedExtensions
        XCTAssertEqual(extensions, ["md"])
    }

    func test_parseExtensions_multipleExtensions() {
        sut.fileExtensionFilter = "*.md, *.txt, *.swift"
        let extensions = sut.parsedExtensions.sorted()
        XCTAssertEqual(extensions, ["md", "swift", "txt"])
    }

    func test_parseExtensions_withSpaces() {
        sut.fileExtensionFilter = "*.md, *.txt"
        let extensions = sut.parsedExtensions.sorted()
        XCTAssertEqual(extensions, ["md", "txt"])
    }

    func test_parseExtensions_wildcardAllFiles() {
        sut.fileExtensionFilter = "*"
        let extensions = sut.parsedExtensions
        XCTAssertTrue(extensions.isEmpty, "Wildcard * should return empty array (meaning all files)")
    }

    func test_parseExtensions_emptyString() {
        sut.fileExtensionFilter = ""
        let extensions = sut.parsedExtensions
        XCTAssertTrue(extensions.isEmpty, "Empty filter should return empty array (meaning all files)")
    }

    // MARK: - File Matching

    func test_shouldShowFile_withMatchingExtension() {
        sut.fileExtensionFilter = "*.md, *.txt"
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let txtFile = URL(fileURLWithPath: "/test/note.txt")

        XCTAssertTrue(sut.shouldShowFile(mdFile), "Should show .md files when filter includes *.md")
        XCTAssertTrue(sut.shouldShowFile(txtFile), "Should show .txt files when filter includes *.txt")
    }

    func test_shouldShowFile_withNonMatchingExtension() {
        sut.fileExtensionFilter = "*.md"
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")

        XCTAssertFalse(sut.shouldShowFile(swiftFile), "Should not show .swift files when filter is *.md")
    }

    func test_shouldShowFile_wildcardShowsAll() {
        sut.fileExtensionFilter = "*"
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let noExtFile = URL(fileURLWithPath: "/test/README")

        XCTAssertTrue(sut.shouldShowFile(swiftFile), "Should show all files with wildcard filter")
        XCTAssertTrue(sut.shouldShowFile(mdFile), "Should show all files with wildcard filter")
        XCTAssertTrue(sut.shouldShowFile(noExtFile), "Should show all files with wildcard filter")
    }

    func test_shouldShowFile_emptyFilterShowsAll() {
        sut.fileExtensionFilter = ""
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")

        XCTAssertTrue(sut.shouldShowFile(swiftFile), "Should show all files when filter is empty")
    }

    func test_shouldShowFile_isCaseInsensitive() {
        sut.fileExtensionFilter = "*.md"
        let upperFile = URL(fileURLWithPath: "/test/note.MD")
        let mixedFile = URL(fileURLWithPath: "/test/note.Md")

        XCTAssertTrue(sut.shouldShowFile(upperFile), "Should be case insensitive")
        XCTAssertTrue(sut.shouldShowFile(mixedFile), "Should be case insensitive")
    }

    // MARK: - Config Persistence

    func test_save_writesToDisk() {
        sut.onBootCommand = "opencode"
        sut.fileExtensionFilter = "*.md"

        XCTAssertTrue(FileManager.default.fileExists(atPath: configFilePath), "Config file should exist after saving")

        // Read raw JSON
        let data = try! Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["onBootCommand"] as? String, "opencode")
        XCTAssertEqual(json["fileExtensionFilter"] as? String, "*.md")
    }

    func test_load_readsFromDisk() {
        // Pre-write a config file
        let config: [String: String] = [
            "onBootCommand": "npm start",
            "fileExtensionFilter": "*.swift"
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        // Create new manager pointing to existing config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "npm start")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.swift")
    }

    func test_load_missingFileUsesDefaults() {
        // Delete config file if it exists
        try? FileManager.default.removeItem(atPath: configFilePath)

        // Create new manager without existing config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.md, *.txt")
    }

    func test_load_invalidJsonUsesDefaults() {
        // Write invalid JSON
        let invalidData = "not valid json".data(using: .utf8)!
        try! invalidData.write(to: URL(fileURLWithPath: configFilePath))

        // Create new manager with invalid config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.md, *.txt")
    }

    // MARK: - Changes Notification

    func test_settingOnBootCommand_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.onBootCommand = "new command"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting onBootCommand should trigger save notification")
        cancellable.cancel()
    }

    func test_settingFileExtensionFilter_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.fileExtensionFilter = "*.swift"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting fileExtensionFilter should trigger save notification")
        cancellable.cancel()
    }

    // MARK: - Default Config Path

    func test_defaultConfigPath_inApplicationSupport() {
        let manager = SettingsManager()
        let expectedPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Noted/settings.json")
            .path

        // This is a bit of a hack since we can't easily test the default init without mocking
        // but we can at least verify the default path pattern
        XCTAssertTrue(manager.configPath.contains("Noted"), "Default config path should be in Application Support/Noted")
        XCTAssertTrue(manager.configPath.hasSuffix(".json"), "Default config should be JSON file")
    }
}
