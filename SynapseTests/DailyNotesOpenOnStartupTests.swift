import XCTest
@testable import Synapse

/// Tests for Daily Notes Open On Startup feature
final class DailyNotesOpenOnStartupTests: XCTestCase {

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

    // MARK: - Default State

    func test_initialState_dailyNotesOpenOnStartup_defaultsToFalse() {
        XCTAssertFalse(sut.dailyNotesOpenOnStartup, "dailyNotesOpenOnStartup should default to false")
    }

    // MARK: - Setting Behavior

    func test_dailyNotesOpenOnStartup_canBeSetToFalse() {
        sut.dailyNotesOpenOnStartup = false
        XCTAssertFalse(sut.dailyNotesOpenOnStartup)
    }

    func test_dailyNotesOpenOnStartup_canBeSetToTrue() {
        sut.dailyNotesOpenOnStartup = false
        sut.dailyNotesOpenOnStartup = true
        XCTAssertTrue(sut.dailyNotesOpenOnStartup)
    }

    // MARK: - Persistence

    func test_dailyNotesOpenOnStartup_persistsToDisk() {
        sut.dailyNotesOpenOnStartup = false

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertFalse(newManager.dailyNotesOpenOnStartup, "Setting should persist to disk")
    }

    func test_dailyNotesOpenOnStartup_loadsFromDisk() {
        sut.dailyNotesOpenOnStartup = true

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(newManager.dailyNotesOpenOnStartup, "Setting should load from disk")
    }

    func test_dailyNotesOpenOnStartup_appearsInSavedJson() throws {
        sut.dailyNotesOpenOnStartup = true

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["dailyNotesOpenOnStartup"] as? Bool, true)
    }

    // MARK: - Load with Missing Value

    func test_load_missingDailyNotesOpenOnStartup_defaultsToFalse() throws {
        // Write config without dailyNotesOpenOnStartup
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "dailyNotesEnabled": true,
            "dailyNotesFolder": "daily",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertFalse(newManager.dailyNotesOpenOnStartup, "Should default to false when missing from config")
    }

    // MARK: - Save Notification

    func test_settingDailyNotesOpenOnStartup_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.dailyNotesOpenOnStartup = false

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting should trigger save notification")
        cancellable.cancel()
    }
}
