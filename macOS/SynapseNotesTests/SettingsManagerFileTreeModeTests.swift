import XCTest
@testable import Synapse

/// Tests for SettingsManager: fileTreeMode persistence
final class SettingsManagerFileTreeModeTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Default

    func test_fileTreeMode_defaultsToFolder() {
        XCTAssertEqual(sut.fileTreeMode, .folder)
    }

    // MARK: - Setting

    func test_fileTreeMode_canBeSetToFile() {
        sut.fileTreeMode = .file
        XCTAssertEqual(sut.fileTreeMode, .file)
    }

    func test_fileTreeMode_canBeSetBackToFolder() {
        sut.fileTreeMode = .file
        sut.fileTreeMode = .folder
        XCTAssertEqual(sut.fileTreeMode, .folder)
    }

    // MARK: - Persistence

    func test_fileTreeMode_folder_persistsToDisk() {
        sut.fileTreeMode = .folder
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.fileTreeMode, .folder)
    }

    func test_fileTreeMode_file_persistsToDisk() {
        sut.fileTreeMode = .file
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.fileTreeMode, .file)
    }

    func test_fileTreeMode_appearsInSavedJSON() {
        sut.fileTreeMode = .file
        let data = try! Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["fileTreeMode"] as? String, "file")
    }

    func test_fileTreeMode_missingFromJSON_defaultsToFolder() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.fileTreeMode, .folder)
    }

    func test_fileTreeMode_unknownValueInJSON_defaultsToFolder() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "autoSave": false,
            "autoPush": false,
            "fileTreeMode": "grid"
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.fileTreeMode, .folder)
    }

    // MARK: - Observable

    func test_fileTreeMode_change_triggersObjectWillChange() {
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { _ in changeCount += 1 }
        sut.fileTreeMode = .file
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    // MARK: - FileTreeMode enum

    func test_fileTreeMode_rawValues() {
        XCTAssertEqual(FileTreeMode.folder.rawValue, "folder")
        XCTAssertEqual(FileTreeMode.file.rawValue, "file")
    }

    func test_fileTreeMode_allCasesCount() {
        XCTAssertEqual(FileTreeMode.allCases.count, 2)
    }

    func test_fileTreeMode_roundTripViaRawValue() {
        XCTAssertEqual(FileTreeMode(rawValue: "folder"), .folder)
        XCTAssertEqual(FileTreeMode(rawValue: "file"), .file)
        XCTAssertNil(FileTreeMode(rawValue: "unknown"))
    }
}
