import XCTest
@testable import Synapse

// MARK: - SettingsManager Theme persistence tests

final class SettingsManagerThemeTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var vaultDir: URL!
    var globalConfigPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vaultDir = tempDir.appendingPathComponent("Vault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        globalConfigPath = tempDir.appendingPathComponent("global-settings.yml").path
        sut = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Default state

    func test_defaultActiveThemeName_isSynapseDark() {
        XCTAssertEqual(sut.activeThemeName, "Synapse (Dark)")
    }

    func test_defaultCustomThemes_isEmpty() {
        XCTAssertTrue(sut.customThemes.isEmpty)
    }

    // MARK: - Active theme persistence

    func test_activeThemeName_persistsToVaultConfig() {
        sut.activeThemeName = "Dracula (Dark)"

        let reloaded = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(reloaded.activeThemeName, "Dracula (Dark)")
    }

    func test_activeThemeName_missingFromYAMLDefaultsToSynapseDark() {
        // Write vault YAML without activeThemeName key
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        let configFile = vaultDir.appendingPathComponent(".synapse/settings.yml")
        try! FileManager.default.createDirectory(
            at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! yaml.write(to: configFile, atomically: true, encoding: .utf8)

        let mgr = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(mgr.activeThemeName, "Synapse (Dark)")
    }

    // MARK: - Custom themes persistence

    func test_customThemes_persistToVaultConfig() {
        let custom = AppTheme(name: "My Theme", colors: ["accent": "#ff0000"])
        sut.customThemes = [custom]

        let reloaded = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(reloaded.customThemes.count, 1)
        XCTAssertEqual(reloaded.customThemes.first?.name, "My Theme")
        XCTAssertEqual(reloaded.customThemes.first?.colors["accent"], "#ff0000")
    }

    func test_customThemes_multipleThemesPersist() {
        sut.customThemes = [
            AppTheme(name: "Theme A", colors: ["accent": "#aaaaaa"]),
            AppTheme(name: "Theme B", colors: ["accent": "#bbbbbb"]),
        ]

        let reloaded = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(reloaded.customThemes.count, 2)
        XCTAssertEqual(reloaded.customThemes[0].name, "Theme A")
        XCTAssertEqual(reloaded.customThemes[1].name, "Theme B")
    }

    // MARK: - activeTheme computed property

    func test_activeTheme_returnsMatchingBuiltIn() {
        sut.activeThemeName = "Dracula (Dark)"
        XCTAssertEqual(sut.activeTheme.name, "Dracula (Dark)")
        XCTAssertTrue(sut.activeTheme.isBuiltIn)
    }

    func test_activeTheme_returnsMatchingCustomTheme() {
        let custom = AppTheme(name: "My Vibe", colors: ["accent": "#ff00ff"])
        sut.customThemes = [custom]
        sut.activeThemeName = "My Vibe"
        XCTAssertEqual(sut.activeTheme.name, "My Vibe")
        XCTAssertFalse(sut.activeTheme.isBuiltIn)
    }

    func test_activeTheme_fallsBackToSynapseDarkForUnknownName() {
        sut.activeThemeName = "NonExistent Theme"
        XCTAssertEqual(sut.activeTheme.name, "Synapse (Dark)")
    }

    // MARK: - allThemes computed property

    func test_allThemes_containsBuiltInsFirst() {
        let all = sut.allThemes
        let names = all.map(\.name)
        XCTAssertTrue(names.prefix(4).contains("Synapse (Dark)"))
        XCTAssertTrue(names.prefix(4).contains("Synapse (Light)"))
        XCTAssertTrue(names.prefix(4).contains("Solarized (Dark)"))
        XCTAssertTrue(names.prefix(4).contains("Dracula (Dark)"))
    }

    func test_allThemes_appendsCustomThemesAfterBuiltIns() {
        sut.customThemes = [
            AppTheme(name: "Custom 1", colors: [:]),
            AppTheme(name: "Custom 2", colors: [:]),
        ]
        let all = sut.allThemes
        let builtInCount = AppTheme.builtInThemes.count
        XCTAssertEqual(all.count, builtInCount + 2)
        XCTAssertEqual(all[builtInCount].name, "Custom 1")
        XCTAssertEqual(all[builtInCount + 1].name, "Custom 2")
    }

    // MARK: - Theme stored in vault config, not global config

    func test_activeThemeName_storedInVaultConfigNotGlobal() {
        sut.activeThemeName = "Solarized (Dark)"

        let vaultYAML = try! String(
            contentsOf: vaultDir.appendingPathComponent(".synapse/settings.yml"), encoding: .utf8)
        let globalYAML = (try? String(contentsOfFile: globalConfigPath, encoding: .utf8)) ?? ""

        XCTAssertTrue(vaultYAML.contains("activeThemeName"), "activeThemeName should be in vault config")
        XCTAssertFalse(globalYAML.contains("activeThemeName"), "activeThemeName should NOT be in global config")
    }
}
