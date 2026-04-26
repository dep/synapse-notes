import XCTest
@testable import Synapse

/// Tests for SettingsManager.browserStartupURL — the URL that the mini-browser
/// pane opens to when first shown.
///
/// This setting was added alongside the browser pane feature and has no
/// existing coverage.  If persistence regresses, the browser pane always
/// resets to its built-in default, silently ignoring the user's preference.
final class SettingsManagerBrowserStartupURLTests: XCTestCase {

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

    func test_browserStartupURL_defaultsToEmptyString() {
        XCTAssertEqual(sut.browserStartupURL, "",
                       "browserStartupURL should default to an empty string")
    }

    // MARK: - Setting the URL

    func test_browserStartupURL_canBeSet() {
        sut.browserStartupURL = "https://example.com"
        XCTAssertEqual(sut.browserStartupURL, "https://example.com")
    }

    func test_browserStartupURL_canBeCleared() {
        sut.browserStartupURL = "https://example.com"
        sut.browserStartupURL = ""
        XCTAssertEqual(sut.browserStartupURL, "")
    }

    func test_browserStartupURL_acceptsArbitraryString() {
        let custom = "file:///Users/dev/index.html"
        sut.browserStartupURL = custom
        XCTAssertEqual(sut.browserStartupURL, custom)
    }

    // MARK: - Persistence

    func test_browserStartupURL_persistsToDisk() {
        sut.browserStartupURL = "https://synapse-delta-nine.vercel.app/"

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.browserStartupURL, "https://synapse-delta-nine.vercel.app/",
                       "Browser startup URL should persist to disk and survive a reload")
    }

    func test_browserStartupURL_persistsEmptyString() {
        sut.browserStartupURL = "https://example.com"
        sut.browserStartupURL = ""

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(reloaded.browserStartupURL, "",
                       "Clearing the browser startup URL should persist as empty")
    }

    func test_browserStartupURL_missingFromConfig_defaultsToEmpty() {
        // Write a settings file that does not include the browserStartupURL key.
        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt'
        templatesDirectory: templates
        autoSave: false
        autoPush: false
        """
        try! yaml.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(manager.browserStartupURL, "",
                       "A missing browserStartupURL key should produce an empty string, not a crash")
    }

    // MARK: - Change notifications

    func test_browserStartupURL_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }

        sut.browserStartupURL = "https://example.com"

        XCTAssertGreaterThanOrEqual(notifyCount, 1,
                                    "Updating browserStartupURL should trigger objectWillChange")
        cancellable.cancel()
    }

    // MARK: - Vault-specific isolation

    func test_browserStartupURL_isVaultSpecificSetting() {
        // browserStartupURL is stored in the vault's .synapse/settings.yml, so two
        // different vaults can each have their own browser start page.
        let vault1 = tempDir.appendingPathComponent("Vault1", isDirectory: true)
        let vault2 = tempDir.appendingPathComponent("Vault2", isDirectory: true)
        try! FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)

        let globalConfig = tempDir.appendingPathComponent("global-settings.yml").path

        let m1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfig)
        m1.browserStartupURL = "https://v1.example.com"

        let m2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfig)
        m2.browserStartupURL = "https://v2.example.com"

        // Reload each vault and confirm their URLs are independent.
        let r1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfig)
        let r2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfig)

        XCTAssertEqual(r1.browserStartupURL, "https://v1.example.com",
                       "Vault 1's browser startup URL should be vault-specific")
        XCTAssertEqual(r2.browserStartupURL, "https://v2.example.com",
                       "Vault 2's browser startup URL should be independent of vault 1")
    }
}
