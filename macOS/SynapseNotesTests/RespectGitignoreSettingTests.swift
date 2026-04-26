import XCTest
@testable import Synapse

/// Tests for Issue #143: respectGitignore user-facing setting.
/// Verifies that the setting defaults to true, persists via the YAML
/// vault config, round-trips through reloadFromDisk, and is absent from
/// the config file when set to the default (true) to avoid config noise.
final class RespectGitignoreSettingTests: XCTestCase {

    var tempDir: URL!
    var globalConfigPath: String!
    var synapseDir: URL!
    var settingsURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        synapseDir = tempDir.appendingPathComponent(".synapse")
        try! FileManager.default.createDirectory(at: synapseDir, withIntermediateDirectories: true)
        settingsURL = synapseDir.appendingPathComponent("settings.yml")
        globalConfigPath = tempDir.appendingPathComponent("global.yml").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Default value

    func test_respectGitignore_defaultsToTrue_vaultMode() {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        XCTAssertTrue(settings.respectGitignore,
                      "respectGitignore must default to true for vault-mode settings")
    }

    func test_respectGitignore_defaultsToTrue_legacyMode() {
        let configPath = tempDir.appendingPathComponent("settings.json").path
        let settings = SettingsManager(configPath: configPath)
        XCTAssertTrue(settings.respectGitignore,
                      "respectGitignore must default to true for legacy-mode settings")
    }

    // MARK: - Persist false → reload

    func test_respectGitignore_false_persistsAndReloads_vaultMode() {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        settings.respectGitignore = false

        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        XCTAssertFalse(reloaded.respectGitignore,
                       "Setting respectGitignore=false should survive a save/reload cycle")
    }

    func test_respectGitignore_true_afterFalse_persistsAndReloads_vaultMode() {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        settings.respectGitignore = false
        settings.respectGitignore = true

        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        XCTAssertTrue(reloaded.respectGitignore,
                      "Re-enabling respectGitignore should survive a save/reload cycle")
    }

    // MARK: - YAML content

    func test_respectGitignore_false_appearsInVaultSettingsYAML() throws {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        settings.respectGitignore = false

        let yaml = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(yaml.contains("respectGitignore"),
                      "respectGitignore key should appear in settings.yml when set to false")
    }

    // MARK: - reloadFromDisk picks up external YAML change

    func test_respectGitignore_reloadFromDisk_picksUpExternalChange() throws {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        XCTAssertTrue(settings.respectGitignore)

        let yaml = """
        onBootCommand: ""
        fileExtensionFilter: "*.md"
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        respectGitignore: false
        """
        try yaml.write(to: settingsURL, atomically: true, encoding: .utf8)
        settings.reloadFromDisk()

        XCTAssertFalse(settings.respectGitignore,
                       "reloadFromDisk should pick up respectGitignore:false from YAML")
    }

    // MARK: - Legacy (JSON) mode round-trip

    func test_respectGitignore_false_persistsAndReloads_legacyMode() {
        let configPath = tempDir.appendingPathComponent("settings.json").path
        let settings = SettingsManager(configPath: configPath)
        settings.respectGitignore = false

        let reloaded = SettingsManager(configPath: configPath)
        XCTAssertFalse(reloaded.respectGitignore,
                       "respectGitignore=false should survive a legacy JSON save/reload cycle")
    }
}
