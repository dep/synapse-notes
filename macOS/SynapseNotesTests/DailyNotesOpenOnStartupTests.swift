import XCTest
@testable import Synapse

/// Tests for Launch Behavior feature
final class LaunchBehaviorTests: XCTestCase {

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

    func test_initialState_launchBehavior_defaultsToPreviouslyOpenNotes() {
        XCTAssertEqual(sut.launchBehavior, .previouslyOpenNotes, "launchBehavior should default to previouslyOpenNotes")
    }
    
    func test_initialState_launchSpecificNotePath_defaultsToEmpty() {
        XCTAssertEqual(sut.launchSpecificNotePath, "", "launchSpecificNotePath should default to empty string")
    }

    // MARK: - Setting Behavior

    func test_launchBehavior_canBeChanged() {
        sut.launchBehavior = .previouslyOpenNotes
        XCTAssertEqual(sut.launchBehavior, .previouslyOpenNotes)
        
        sut.launchBehavior = .dailyNote
        XCTAssertEqual(sut.launchBehavior, .dailyNote)
        
        sut.launchBehavior = .specificNote
        XCTAssertEqual(sut.launchBehavior, .specificNote)
    }
    
    func test_launchSpecificNotePath_canBeSet() {
        sut.launchSpecificNotePath = ""
        XCTAssertEqual(sut.launchSpecificNotePath, "")
        
        sut.launchSpecificNotePath = "notes/daily.md"
        XCTAssertEqual(sut.launchSpecificNotePath, "notes/daily.md")
    }

    // MARK: - Persistence

    func test_launchBehavior_persistsToDisk() {
        sut.launchBehavior = .dailyNote

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.launchBehavior, .dailyNote, "Setting should persist to disk")
    }
    
    func test_launchSpecificNotePath_persistsToDisk() {
        sut.launchSpecificNotePath = "notes/daily.md"

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.launchSpecificNotePath, "notes/daily.md", "Setting should persist to disk")
    }

    func test_launchBehavior_appearsInSavedJson() throws {
        sut.launchBehavior = .dailyNote

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["launchBehavior"] as? String, "dailyNote")
    }
    
    func test_launchSpecificNotePath_appearsInSavedJson() throws {
        sut.launchSpecificNotePath = "notes/daily.md"

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["launchSpecificNotePath"] as? String, "notes/daily.md")
    }

    // MARK: - Load with Missing Value

    func test_load_missingLaunchBehavior_defaultsToPreviouslyOpenNotes() throws {
        // Write config without launchBehavior
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
        XCTAssertEqual(newManager.launchBehavior, .previouslyOpenNotes, "Should default to previouslyOpenNotes when missing from config")
    }

    // MARK: - Migration from dailyNotesOpenOnStartup

    func test_load_withDailyNotesOpenOnStartupTrue_migratesToDailyNote() throws {
        // Write config with legacy dailyNotesOpenOnStartup = true
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "dailyNotesEnabled": true,
            "dailyNotesFolder": "daily",
            "dailyNotesOpenOnStartup": true,
            "autoSave": false,
            "autoPush": false
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.launchBehavior, .dailyNote, "Should migrate dailyNotesOpenOnStartup=true to launchBehavior=.dailyNote")
    }
    
    func test_load_withDailyNotesOpenOnStartupFalse_migratesToPreviouslyOpenNotes() throws {
        // Write config with legacy dailyNotesOpenOnStartup = false
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "dailyNotesEnabled": true,
            "dailyNotesFolder": "daily",
            "dailyNotesOpenOnStartup": false,
            "autoSave": false,
            "autoPush": false
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.launchBehavior, .previouslyOpenNotes, "Should migrate dailyNotesOpenOnStartup=false to launchBehavior=.previouslyOpenNotes")
    }

    // MARK: - Save Notification

    func test_settingLaunchBehavior_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.launchBehavior = .dailyNote

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting should trigger save notification")
        cancellable.cancel()
    }
    
    func test_settingLaunchSpecificNotePath_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.launchSpecificNotePath = "notes/daily.md"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting should trigger save notification")
        cancellable.cancel()
    }
}
