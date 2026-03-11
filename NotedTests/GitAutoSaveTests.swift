import XCTest
@testable import Noted

/// Tests for Git auto-save and auto-push settings
final class GitAutoSaveTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        configFilePath = tempDir.appendingPathComponent("noted-settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Auto-Save Setting

    func test_autoSave_defaultsToFalse() {
        XCTAssertFalse(sut.autoSave, "Auto-save should be disabled by default")
    }

    func test_autoSave_canBeEnabled() {
        sut.autoSave = true
        XCTAssertTrue(sut.autoSave)
    }

    func test_autoSave_canBeDisabled() {
        sut.autoSave = true
        sut.autoSave = false
        XCTAssertFalse(sut.autoSave)
    }

    func test_autoSave_persistsToDisk() {
        sut.autoSave = true

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(newManager.autoSave, "Auto-save should persist to disk")
    }

    // MARK: - Auto-Push Setting

    func test_autoPush_defaultsToFalse() {
        XCTAssertFalse(sut.autoPush, "Auto-push should be disabled by default")
    }

    func test_autoPush_canBeEnabled() {
        sut.autoPush = true
        XCTAssertTrue(sut.autoPush)
    }

    func test_autoPush_canBeDisabled() {
        sut.autoPush = true
        sut.autoPush = false
        XCTAssertFalse(sut.autoPush)
    }

    func test_autoPush_persistsToDisk() {
        sut.autoPush = true

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(newManager.autoPush, "Auto-push should persist to disk")
    }

    // MARK: - Setting Triggers Save

    func test_settingAutoSave_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.autoSave = true

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting autoSave should trigger save notification")
        cancellable.cancel()
    }

    func test_settingAutoPush_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.autoPush = true

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting autoPush should trigger save notification")
        cancellable.cancel()
    }

    // MARK: - Config File Format

    func test_save_includesBothSettings() {
        sut.autoSave = true
        sut.autoPush = true

        let data = try! Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["autoSave"] as? Bool, true)
        XCTAssertEqual(json["autoPush"] as? Bool, true)
    }

    func test_load_withBothSettings() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md",
            "autoSave": true,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertTrue(newManager.autoSave)
        XCTAssertFalse(newManager.autoPush)
    }

    func test_load_missingAutoSaveDefaultsToFalse() {
        let config: [String: String] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md"
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertFalse(newManager.autoSave)
        XCTAssertFalse(newManager.autoPush)
    }
}
