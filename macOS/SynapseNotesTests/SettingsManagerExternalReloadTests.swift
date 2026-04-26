import XCTest
import Combine
@testable import Synapse

final class SettingsManagerExternalReloadTests: XCTestCase {
    private var tempDir: URL!
    private var globalConfigPath: String!
    private var cancellables: Set<AnyCancellable> = []

    private var settingsURL: URL {
        tempDir.appendingPathComponent(".synapse/settings.yml")
    }

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".synapse"), withIntermediateDirectories: true)
        globalConfigPath = tempDir.appendingPathComponent("global-settings.yml").path
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_externalVaultSettingsChange_doesNotReloadPublishedValuesAutomatically() throws {
        let manager = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        XCTAssertFalse(manager.dailyNotesEnabled)

        let reloadExpectation = expectation(description: "does not auto-reload after external vault settings change")
        reloadExpectation.isInverted = true
        manager.$dailyNotesEnabled
            .dropFirst()
            .sink { enabled in
                if enabled {
                    reloadExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let yaml = """
        onBootCommand: echo hi
        fileExtensionFilter: "*.md, *.txt"
        templatesDirectory: templates
        dailyNotesEnabled: true
        autoSave: false
        autoPush: false
        """

        try yaml.write(to: settingsURL, atomically: true, encoding: .utf8)

        wait(for: [reloadExpectation], timeout: 1.0)
        XCTAssertFalse(manager.dailyNotesEnabled)
    }

    func test_refreshAllFiles_reloadsExternalVaultSettingsChange() throws {
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalConfigPath)
        let appState = AppState(settings: settings)
        appState.rootURL = tempDir
        XCTAssertFalse(appState.settings.dailyNotesEnabled)

        let yaml = """
        onBootCommand: echo hi
        fileExtensionFilter: "*.md, *.txt, *.json"
        templatesDirectory: templates
        dailyNotesEnabled: true
        autoSave: false
        autoPush: false
        """
        try yaml.write(to: settingsURL, atomically: true, encoding: .utf8)

        appState.refreshAllFiles()

        XCTAssertTrue(appState.settings.dailyNotesEnabled)
        XCTAssertEqual(appState.settings.fileExtensionFilter, "*.md, *.txt, *.json")
    }

    // MARK: - reloadFromDisk — global-only path (vaultRoot == nil)

    func test_reloadFromDisk_globalOnlyMode_loadsUpdatedGithubPAT() throws {
        let globalConfigURL = tempDir.appendingPathComponent("global-settings.yml")
        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigURL.path)
        XCTAssertEqual(manager.githubPAT, "")

        let yaml = "githubPAT: ghp_reloadtest\n"
        try yaml.write(to: globalConfigURL, atomically: true, encoding: .utf8)

        manager.reloadFromDisk()

        XCTAssertEqual(manager.githubPAT, "ghp_reloadtest",
                       "reloadFromDisk in global-only mode should load the updated githubPAT from disk")
    }

    func test_reloadFromDisk_globalOnlyMode_resetsVaultSpecificFieldsToDefaults() throws {
        let globalConfigURL = tempDir.appendingPathComponent("global-settings.yml")
        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigURL.path)

        // Mutate a vault-specific field in-memory.
        manager.dailyNotesEnabled = true
        XCTAssertTrue(manager.dailyNotesEnabled)

        // Write a global config that does NOT include vault-specific fields.
        let yaml = "githubPAT: ghp_test\n"
        try yaml.write(to: globalConfigURL, atomically: true, encoding: .utf8)

        manager.reloadFromDisk()

        // applyNoVaultDefaults() resets dailyNotesEnabled to false before the global
        // config is applied, so the in-memory mutation should not survive.
        XCTAssertFalse(manager.dailyNotesEnabled,
                       "reloadFromDisk in global-only mode should reset vault-specific fields to their defaults")
    }

    func test_reloadFromDisk_globalOnlyMode_updatedValueOverridesPreviousGlobalConfig() throws {
        let globalConfigURL = tempDir.appendingPathComponent("global-settings.yml")

        let initialYaml = "githubPAT: ghp_initial\n"
        try initialYaml.write(to: globalConfigURL, atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigURL.path)
        XCTAssertEqual(manager.githubPAT, "ghp_initial")

        let updatedYaml = "githubPAT: ghp_updated\n"
        try updatedYaml.write(to: globalConfigURL, atomically: true, encoding: .utf8)

        manager.reloadFromDisk()

        XCTAssertEqual(manager.githubPAT, "ghp_updated",
                       "reloadFromDisk in global-only mode should pick up the latest value from disk")
    }

    func test_reloadFromDisk_globalOnlyMode_missingConfigFile_keepsDefaults() throws {
        // Use a path inside a non-existent subdirectory so no file is ever created there.
        let globalConfigURL = tempDir
            .appendingPathComponent("no-such-dir", isDirectory: true)
            .appendingPathComponent("settings.yml")

        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigURL.path)

        // The file does not exist; defaults should apply.
        XCTAssertEqual(manager.githubPAT, "",
                       "Initial githubPAT should default to empty when config file is absent")

        // Reloading from the still-missing path should keep the default.
        manager.reloadFromDisk()

        XCTAssertEqual(manager.githubPAT, "",
                       "reloadFromDisk with a missing global config should leave githubPAT at its default")
    }
}
