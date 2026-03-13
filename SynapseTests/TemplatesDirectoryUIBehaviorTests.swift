import XCTest
@testable import Synapse

/// Integration test for templates directory UI behavior
final class TemplatesDirectoryUIBehaviorTests: XCTestCase {

    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("settings.json").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_templatesDirectory_hiddenFolder_roundTripThroughDisk() throws {
        // Given - Simulate user typing ".templates" in the UI
        let settings = SettingsManager(configPath: configFilePath)
        settings.templatesDirectory = ".templates"
        
        // When - Simulate app restart by creating new SettingsManager
        let newSettings = SettingsManager(configPath: configFilePath)
        
        // Then
        XCTAssertEqual(newSettings.templatesDirectory, ".templates", 
                       "Hidden folder should survive app restart")
    }

    func test_templatesDirectory_hiddenFolder_immediatePersistence() throws {
        // Given
        let settings = SettingsManager(configPath: configFilePath)
        
        // When - Set to hidden folder
        settings.templatesDirectory = ".templates"
        
        // Then - Check file immediately
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["templatesDirectory"] as? String, ".templates",
                       "JSON should contain .templates immediately after setting")
    }

    func test_templatesDirectory_multipleChangesWithHiddenFolder() throws {
        // Given
        let settings = SettingsManager(configPath: configFilePath)
        
        // When - Make multiple changes
        settings.templatesDirectory = "templates"
        settings.templatesDirectory = ".templates"
        settings.templatesDirectory = "snippets"
        settings.templatesDirectory = ".hidden"
        
        // Then
        let newSettings = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newSettings.templatesDirectory, ".hidden")
    }

    func test_templatesDirectory_hiddenFolderWithSubdirectory() throws {
        // Given
        let settings = SettingsManager(configPath: configFilePath)
        
        // When - Set to hidden folder with subdirectory path
        settings.templatesDirectory = ".config/templates"
        
        // Then
        let newSettings = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newSettings.templatesDirectory, ".config/templates")
    }

    func test_templatesDirectory_emptyThenHidden() throws {
        // Given - Start with empty
        let settings = SettingsManager(configPath: configFilePath)
        settings.templatesDirectory = ""
        
        // When - Change to hidden folder
        settings.templatesDirectory = ".templates"
        
        // Then
        XCTAssertEqual(settings.templatesDirectory, ".templates")
        
        // And after restart
        let newSettings = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newSettings.templatesDirectory, ".templates")
    }
}
