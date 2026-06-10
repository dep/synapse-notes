import XCTest
@testable import Synapse

/// Tests for GitHub PAT (Personal Access Token) setting in SettingsManager.
/// The PAT lives in a `SecretStore` (the Keychain in production); tests inject an
/// `InMemorySecretStore` so the system keychain is never touched (#256).
final class SettingsManagerGitHubPATTests: XCTestCase {
    var sut: SettingsManager!
    var store: InMemorySecretStore!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("Synapse-settings.json").path
        store = InMemorySecretStore()
        sut = SettingsManager(configPath: configFilePath, githubPATStore: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_githubPATDefaultsToEmpty() {
        XCTAssertEqual(sut.githubPAT, "", "GitHub PAT should default to empty")
    }

    // MARK: - Setting GitHub PAT

    func test_githubPAT_canBeSet() {
        let token = "ghp_1234567890abcdef"
        sut.githubPAT = token
        XCTAssertEqual(sut.githubPAT, token)
    }

    func test_githubPAT_canBeCleared() {
        sut.githubPAT = "ghp_1234567890abcdef"
        sut.githubPAT = ""
        XCTAssertEqual(sut.githubPAT, "")
        XCTAssertNil(store.get(), "Clearing the PAT should delete it from the secret store")
    }

    // MARK: - Keychain Persistence (never the settings file)

    func test_githubPAT_persistsViaSecretStore_notDisk() {
        let token = "ghp_persistencetest123"
        sut.githubPAT = token
        // Force a settings-file write (PAT itself no longer triggers one).
        sut.autoSave = true

        XCTAssertEqual(store.get(), token, "GitHub PAT should be written to the secret store")
        let contents = try! String(contentsOfFile: configFilePath, encoding: .utf8)
        XCTAssertFalse(contents.contains(token), "GitHub PAT must never be written to the settings file")

        // A new instance sharing the same store retrieves the token.
        let newManager = SettingsManager(configPath: configFilePath, githubPATStore: store)
        XCTAssertEqual(newManager.githubPAT, token, "GitHub PAT should round-trip via the secret store")

        // A new instance with a fresh store sees nothing (proves the file holds no PAT).
        let freshManager = SettingsManager(configPath: configFilePath, githubPATStore: InMemorySecretStore())
        XCTAssertEqual(freshManager.githubPAT, "", "GitHub PAT must not be recoverable from disk")
    }

    // MARK: - Setting Publishes Change

    func test_settingGithubPAT_publishesObjectWillChange() {
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            changeCount += 1
        }

        sut.githubPAT = "ghp_test123"

        XCTAssertGreaterThanOrEqual(changeCount, 1, "Setting GitHub PAT should publish objectWillChange")
        cancellable.cancel()
    }

    func test_settingGithubPAT_firesGithubPATDidChange() {
        var changeCount = 0
        let cancellable = sut.githubPATDidChange.sink { _ in
            changeCount += 1
        }

        sut.githubPAT = "ghp_test123"

        XCTAssertEqual(changeCount, 1, "Setting GitHub PAT should fire githubPATDidChange")
        cancellable.cancel()
    }

    // MARK: - Loading from Config

    func test_load_missingGitHubPATUsesDefault() {
        // Write config without GitHub PAT field
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath, githubPATStore: InMemorySecretStore())
        XCTAssertEqual(newManager.githubPAT, "", "Missing GitHub PAT should default to empty")
    }

    // MARK: - One-time Migration to the Secret Store

    func test_load_legacyJSONWithGitHubPAT_migratesToSecretStoreAndScrubsFile() {
        let token = "ghp_loadedfromconfig"
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "autoSave": false,
            "autoPush": false,
            "githubPAT": token
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let migrationStore = InMemorySecretStore()
        let newManager = SettingsManager(configPath: configFilePath, githubPATStore: migrationStore)

        XCTAssertEqual(newManager.githubPAT, token, "Migrated PAT should remain available in memory")
        XCTAssertEqual(migrationStore.get(), token, "Migration should write the PAT to the secret store")
        let contents = try! String(contentsOfFile: configFilePath, encoding: .utf8)
        XCTAssertFalse(contents.contains(token), "Migration should scrub the PAT from the settings file")
    }

    func test_load_legacyYAMLWithGitHubPAT_migratesToSecretStoreAndScrubsFile() {
        let token = "ghp_yamlmigration"
        let yaml = """
        onBootCommand: ""
        fileExtensionFilter: "*.md, *.txt"
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        githubPAT: \(token)
        """
        try! yaml.write(toFile: configFilePath, atomically: true, encoding: .utf8)

        let migrationStore = InMemorySecretStore()
        let newManager = SettingsManager(configPath: configFilePath, githubPATStore: migrationStore)

        XCTAssertEqual(newManager.githubPAT, token, "Migrated PAT should remain available in memory")
        XCTAssertEqual(migrationStore.get(), token, "Migration should write the PAT to the secret store")
        let contents = try! String(contentsOfFile: configFilePath, encoding: .utf8)
        XCTAssertFalse(contents.contains(token), "Migration should scrub the PAT from the settings file")
    }

    func test_load_globalConfigWithGitHubPAT_migratesToSecretStoreAndScrubsFile() {
        let token = "ghp_globalmigration"
        let globalPath = tempDir.appendingPathComponent("global-settings.yml").path
        try! "githubPAT: \(token)\n".write(toFile: globalPath, atomically: true, encoding: .utf8)

        let migrationStore = InMemorySecretStore()
        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalPath, githubPATStore: migrationStore)

        XCTAssertEqual(manager.githubPAT, token, "Migrated PAT should remain available in memory")
        XCTAssertEqual(migrationStore.get(), token, "Migration should write the PAT to the secret store")
        let contents = try! String(contentsOfFile: globalPath, encoding: .utf8)
        XCTAssertFalse(contents.contains(token), "Migration should scrub the PAT from the global settings file")
    }

    func test_load_vaultModeGlobalConfigWithGitHubPAT_migratesAndScrubsAllFiles() {
        let token = "ghp_vaultmodemigration"
        let vaultDir = tempDir.appendingPathComponent("vault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalPath = tempDir.appendingPathComponent("global-settings.yml").path
        try! "githubPAT: \(token)\n".write(toFile: globalPath, atomically: true, encoding: .utf8)

        let migrationStore = InMemorySecretStore()
        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalPath, githubPATStore: migrationStore)

        XCTAssertEqual(manager.githubPAT, token, "Migrated PAT should remain available in memory")
        XCTAssertEqual(migrationStore.get(), token, "Migration should write the PAT to the secret store")
        let globalContents = try! String(contentsOfFile: globalPath, encoding: .utf8)
        XCTAssertFalse(globalContents.contains(token), "Migration should scrub the PAT from the global settings file")
        let vaultSettingsPath = vaultDir.appendingPathComponent(".synapse/settings.yml").path
        if let vaultContents = try? String(contentsOfFile: vaultSettingsPath, encoding: .utf8) {
            XCTAssertFalse(vaultContents.contains(token), "The vault settings file must never contain the PAT")
        }
    }

    // MARK: - Token Presence Check

    func test_hasGitHubPAT_returnsFalseWhenEmpty() {
        sut.githubPAT = ""
        XCTAssertFalse(sut.hasGitHubPAT, "hasGitHubPAT should return false when token is empty")
    }

    func test_hasGitHubPAT_returnsTrueWhenSet() {
        sut.githubPAT = "ghp_sometoken123"
        XCTAssertTrue(sut.hasGitHubPAT, "hasGitHubPAT should return true when token is set")
    }

    func test_hasGitHubPAT_returnsFalseWhenWhitespaceOnly() {
        sut.githubPAT = "   "
        XCTAssertFalse(sut.hasGitHubPAT, "hasGitHubPAT should return false when token is whitespace only")
    }

    func test_hasGitHubPAT_returnsFalseWhenNewlineOnly() {
        sut.githubPAT = "\n"
        XCTAssertFalse(sut.hasGitHubPAT, "hasGitHubPAT should return false when token is a newline character only")
    }

    func test_hasGitHubPAT_returnsFalseWhenMixedWhitespaceAndNewlines() {
        sut.githubPAT = "  \n  \t"
        XCTAssertFalse(sut.hasGitHubPAT, "hasGitHubPAT should return false when token contains only whitespace and newlines")
    }

    // MARK: - flushDebouncedSaveBeforeReloadIfNeeded

    func test_flushDebouncedSaveBeforeReloadIfNeeded_whenNoPendingSave_doesNotCrash() {
        // In the test environment, save() always calls flush() synchronously, so
        // pendingSave is never set. Calling this should be a safe no-op.
        sut.flushDebouncedSaveBeforeReloadIfNeeded()
    }

    func test_flushDebouncedSaveBeforeReloadIfNeeded_settingsSurviveSubsequentReload() {
        // Change the PAT (which lands in the secret store, not the file),
        // call flushDebouncedSaveBeforeReloadIfNeeded (no-op since saves are immediate),
        // then reload from disk. The value must survive because it lives in the store.
        sut.githubPAT = "ghp_survivetest"

        sut.flushDebouncedSaveBeforeReloadIfNeeded()
        sut.reloadFromDisk()

        XCTAssertEqual(sut.githubPAT, "ghp_survivetest",
                       "githubPAT should survive a reload because it lives in the secret store")
    }

    func test_flushDebouncedSaveBeforeReloadIfNeeded_multipleCallsAreIdempotent() {
        sut.githubPAT = "ghp_idempotent"

        sut.flushDebouncedSaveBeforeReloadIfNeeded()
        sut.flushDebouncedSaveBeforeReloadIfNeeded()
        sut.flushDebouncedSaveBeforeReloadIfNeeded()

        sut.reloadFromDisk()

        XCTAssertEqual(sut.githubPAT, "ghp_idempotent",
                       "Multiple flushDebouncedSaveBeforeReloadIfNeeded calls should be safe and idempotent")
    }
}
