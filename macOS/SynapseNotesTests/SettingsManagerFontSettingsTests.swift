import XCTest
@testable import Synapse

/// Tests for SettingsManager font settings (editorBodyFontFamily, editorMonospaceFontFamily, editorFontSize)
/// Issue #139: Allow user to set editor typeface, save to .synapse/settings.yml
///
/// These settings are vault-specific and persist across app restarts.
final class SettingsManagerFontSettingsTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("settings.yml").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_editorBodyFontFamily_defaultsToSystem() {
        XCTAssertEqual(sut.editorBodyFontFamily, "System",
                       "Body font family should default to 'System'")
    }

    func test_editorMonospaceFontFamily_defaultsToSystemMonospace() {
        XCTAssertEqual(sut.editorMonospaceFontFamily, "System Monospace",
                       "Monospace font family should default to 'System Monospace'")
    }

    func test_editorFontSize_defaultsTo15() {
        XCTAssertEqual(sut.editorFontSize, 15,
                       "Font size should default to 15")
    }

    func test_editorLineHeight_defaultsTo16() {
        XCTAssertEqual(sut.editorLineHeight, 1.6,
                       accuracy: 0.001,
                       "Line height should default to 1.6")
    }

    // MARK: - Setting Values

    func test_editorBodyFontFamily_canBeSet() {
        sut.editorBodyFontFamily = "Helvetica"
        XCTAssertEqual(sut.editorBodyFontFamily, "Helvetica")
    }

    func test_editorBodyFontFamily_canBeCleared() {
        sut.editorBodyFontFamily = "Helvetica"
        sut.editorBodyFontFamily = ""
        XCTAssertEqual(sut.editorBodyFontFamily, "")
    }

    func test_editorMonospaceFontFamily_canBeSet() {
        sut.editorMonospaceFontFamily = "Menlo"
        XCTAssertEqual(sut.editorMonospaceFontFamily, "Menlo")
    }

    func test_editorFontSize_canBeSet() {
        sut.editorFontSize = 18
        XCTAssertEqual(sut.editorFontSize, 18)
    }

    func test_editorFontSize_acceptsMinimum8() {
        sut.editorFontSize = 8
        XCTAssertEqual(sut.editorFontSize, 8)
    }

    func test_editorFontSize_acceptsMaximum72() {
        sut.editorFontSize = 72
        XCTAssertEqual(sut.editorFontSize, 72)
    }

    func test_editorLineHeight_canBeSet() {
        sut.editorLineHeight = 1.9
        XCTAssertEqual(sut.editorLineHeight, 1.9, accuracy: 0.001)
    }

    // MARK: - Persistence

    func test_editorBodyFontFamily_persistsToDisk() {
        sut.editorBodyFontFamily = "Georgia"

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.editorBodyFontFamily, "Georgia",
                       "Body font family should persist to disk")
    }

    func test_editorMonospaceFontFamily_persistsToDisk() {
        sut.editorMonospaceFontFamily = "Courier"

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.editorMonospaceFontFamily, "Courier",
                       "Monospace font family should persist to disk")
    }

    func test_editorFontSize_persistsToDisk() {
        sut.editorFontSize = 20

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.editorFontSize, 20,
                       "Font size should persist to disk")
    }

    func test_editorLineHeight_persistsToDisk() {
        sut.editorLineHeight = 1.9

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.editorLineHeight, 1.9,
                       accuracy: 0.001,
                       "Line height should persist to disk")
    }

    func test_allFontSettings_persistTogether() {
        sut.editorBodyFontFamily = "Times New Roman"
        sut.editorMonospaceFontFamily = "Monaco"
        sut.editorFontSize = 24
        sut.editorLineHeight = 1.8

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.editorBodyFontFamily, "Times New Roman")
        XCTAssertEqual(reloaded.editorMonospaceFontFamily, "Monaco")
        XCTAssertEqual(reloaded.editorFontSize, 24)
        XCTAssertEqual(reloaded.editorLineHeight, 1.8, accuracy: 0.001)
    }

    // MARK: - Missing/Invalid Fallback

    func test_editorBodyFontFamily_missingFromConfig_defaultsToSystem() {
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        try! yaml.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(manager.editorBodyFontFamily, "System",
                       "Missing body font should default to 'System'")
    }

    func test_editorMonospaceFontFamily_missingFromConfig_defaultsToSystemMonospace() {
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        try! yaml.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(manager.editorMonospaceFontFamily, "System Monospace",
                       "Missing monospace font should default to 'System Monospace'")
    }

    func test_editorFontSize_missingFromConfig_defaultsTo15() {
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        try! yaml.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(manager.editorFontSize, 15,
                       "Missing font size should default to 15")
    }

    func test_editorLineHeight_missingFromConfig_defaultsTo16() {
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        try! yaml.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(manager.editorLineHeight, 1.6,
                       accuracy: 0.001,
                       "Missing line height should default to 1.6")
    }

    // MARK: - Vault-Specific Isolation

    func test_fontSettings_areVaultSpecific() {
        let vault1 = tempDir.appendingPathComponent("Vault1", isDirectory: true)
        let vault2 = tempDir.appendingPathComponent("Vault2", isDirectory: true)
        try! FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)

        let globalConfig = tempDir.appendingPathComponent("global-settings.yml").path

        let m1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfig)
        m1.editorBodyFontFamily = "Helvetica"
        m1.editorMonospaceFontFamily = "Menlo"
        m1.editorFontSize = 18
        m1.editorLineHeight = 1.4

        let m2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfig)
        m2.editorBodyFontFamily = "Georgia"
        m2.editorMonospaceFontFamily = "Courier"
        m2.editorFontSize = 24
        m2.editorLineHeight = 2.0

        // Reload each vault and confirm their settings are independent
        let r1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfig)
        let r2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfig)

        XCTAssertEqual(r1.editorBodyFontFamily, "Helvetica",
                       "Vault 1's body font should be vault-specific")
        XCTAssertEqual(r1.editorMonospaceFontFamily, "Menlo",
                       "Vault 1's monospace font should be vault-specific")
        XCTAssertEqual(r1.editorFontSize, 18,
                       "Vault 1's font size should be vault-specific")
        XCTAssertEqual(r1.editorLineHeight, 1.4, accuracy: 0.001,
                       "Vault 1's line height should be vault-specific")

        XCTAssertEqual(r2.editorBodyFontFamily, "Georgia",
                       "Vault 2's body font should be independent of vault 1")
        XCTAssertEqual(r2.editorMonospaceFontFamily, "Courier",
                       "Vault 2's monospace font should be independent of vault 1")
        XCTAssertEqual(r2.editorFontSize, 24,
                       "Vault 2's font size should be independent of vault 1")
        XCTAssertEqual(r2.editorLineHeight, 2.0, accuracy: 0.001,
                       "Vault 2's line height should be independent of vault 1")
    }

    // MARK: - Change Notifications

    func test_editorBodyFontFamily_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }

        sut.editorBodyFontFamily = "Arial"

        XCTAssertGreaterThanOrEqual(notifyCount, 1,
                                    "Updating body font should trigger objectWillChange")
        cancellable.cancel()
    }

    func test_editorMonospaceFontFamily_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }

        sut.editorMonospaceFontFamily = "Menlo"

        XCTAssertGreaterThanOrEqual(notifyCount, 1,
                                    "Updating monospace font should trigger objectWillChange")
        cancellable.cancel()
    }

    func test_editorFontSize_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }

        sut.editorFontSize = 20

        XCTAssertGreaterThanOrEqual(notifyCount, 1,
                                    "Updating font size should trigger objectWillChange")
        cancellable.cancel()
    }

    func test_editorLineHeight_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }

        sut.editorLineHeight = 1.8

        XCTAssertGreaterThanOrEqual(notifyCount, 1,
                                    "Updating line height should trigger objectWillChange")
        cancellable.cancel()
    }

    // MARK: - Empty String Handling

    func test_editorBodyFontFamily_emptyStringMeansSystemDefault() {
        sut.editorBodyFontFamily = ""
        XCTAssertEqual(sut.editorBodyFontFamily, "",
                       "Empty body font should be stored as empty (UI shows 'System')")
    }

    func test_editorMonospaceFontFamily_emptyStringMeansSystemDefault() {
        sut.editorMonospaceFontFamily = ""
        XCTAssertEqual(sut.editorMonospaceFontFamily, "",
                       "Empty monospace font should be stored as empty (UI shows 'System Monospace')")
    }
}
