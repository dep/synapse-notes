import XCTest
@testable import Synapse

/// Tests for persistence of new edit-mode settings added in the preview-mode feature.
final class SettingsPersistenceTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("Synapse-settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - defaultEditMode

    func test_defaultEditMode_defaultsToTrue() {
        XCTAssertTrue(sut.defaultEditMode, "defaultEditMode should default to true (edit mode on)")
    }

    func test_defaultEditMode_canBeSetToFalse() {
        sut.defaultEditMode = false
        XCTAssertFalse(sut.defaultEditMode)
    }

    func test_defaultEditMode_persistsToDisk() {
        sut.defaultEditMode = false

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertFalse(reloaded.defaultEditMode, "defaultEditMode=false should survive a reload from disk")
    }

    func test_defaultEditMode_trueValuePersistsToDisk() {
        // Explicitly write true, then reload to verify it round-trips.
        sut.defaultEditMode = false
        sut.defaultEditMode = true

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertTrue(reloaded.defaultEditMode)
    }

    // MARK: - hideMarkdownWhileEditing

    func test_hideMarkdownWhileEditing_defaultsToFalse() {
        XCTAssertFalse(sut.hideMarkdownWhileEditing, "hideMarkdownWhileEditing should default to false")
    }

    func test_hideMarkdownWhileEditing_canBeSetToTrue() {
        sut.hideMarkdownWhileEditing = true
        XCTAssertTrue(sut.hideMarkdownWhileEditing)
    }

    func test_hideMarkdownWhileEditing_persistsToDisk() {
        sut.hideMarkdownWhileEditing = true

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertTrue(reloaded.hideMarkdownWhileEditing, "hideMarkdownWhileEditing=true should survive a reload from disk")
    }

    func test_hideMarkdownWhileEditing_falseValuePersistsToDisk() {
        sut.hideMarkdownWhileEditing = true
        sut.hideMarkdownWhileEditing = false

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertFalse(reloaded.hideMarkdownWhileEditing)
    }

    // MARK: - Vault config round-trip

    func test_vaultConfig_bothSettingsPersistViaYAML() {
        // Create a vault directory with a .synapse folder.
        let notedDir = tempDir.appendingPathComponent(".synapse", isDirectory: true)
        try! FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)

        let vaultSettings = SettingsManager(vaultRoot: tempDir, globalConfigPath: configFilePath)
        vaultSettings.defaultEditMode = false
        vaultSettings.hideMarkdownWhileEditing = true

        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: configFilePath)

        XCTAssertFalse(reloaded.defaultEditMode, "defaultEditMode should persist in vault YAML config")
        XCTAssertTrue(reloaded.hideMarkdownWhileEditing, "hideMarkdownWhileEditing should persist in vault YAML config")
    }
}
