import XCTest
@testable import Synapse

/// Tests for templates directory with hidden folders (starting with dot)
final class TemplatesDirectoryHiddenFolderTests: XCTestCase {

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

    func test_templatesDirectory_canBeSetToHiddenFolder() {
        // When
        sut.templatesDirectory = ".templates"
        
        // Then
        XCTAssertEqual(sut.templatesDirectory, ".templates", "Should allow hidden folder names starting with dot")
    }

    func test_templatesDirectory_hiddenFolder_persistsToDisk() {
        // Given
        sut.templatesDirectory = ".templates"
        
        // When
        let newManager = SettingsManager(configPath: configFilePath)
        
        // Then
        XCTAssertEqual(newManager.templatesDirectory, ".templates", "Hidden folder name should persist to disk")
    }

    func test_templatesDirectory_hiddenFolder_appearsInSavedJson() throws {
        // Given
        sut.templatesDirectory = ".templates"
        
        // When
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Then
        XCTAssertEqual(json["templatesDirectory"] as? String, ".templates")
    }

    func test_templatesDirectory_canBeChangedFromHiddenToNormal() {
        // Given
        sut.templatesDirectory = ".templates"
        
        // When
        sut.templatesDirectory = "templates"
        
        // Then
        XCTAssertEqual(sut.templatesDirectory, "templates")
    }

    func test_templatesDirectory_canBeChangedFromNormalToHidden() {
        // Given
        sut.templatesDirectory = "templates"
        
        // When
        sut.templatesDirectory = ".templates"
        
        // Then
        XCTAssertEqual(sut.templatesDirectory, ".templates")
    }

    func test_templatesDirectory_withMultipleDots() {
        // When
        sut.templatesDirectory = ".hidden.templates"
        
        // Then
        XCTAssertEqual(sut.templatesDirectory, ".hidden.templates")
    }

    func test_templatesDirectory_emptyString_notReplacedWithDefaultUntilRuntime() {
        // When - setting empty string should stay empty in settings
        sut.templatesDirectory = ""
        
        // Then - the setting itself should be empty (runtime defaulting happens elsewhere)
        XCTAssertEqual(sut.templatesDirectory, "", "Empty string should be preserved in settings")
    }
}
