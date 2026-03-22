import XCTest
@testable import Synapse

/// Tests for GitHub PAT (Personal Access Token) setting in SettingsManager
final class SettingsManagerGitHubPATTests: XCTestCase {
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
    }

    func test_githubPAT_persistsToDisk() {
        let token = "ghp_persistencetest123"
        sut.githubPAT = token

        // Create new instance pointing to same config file
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.githubPAT, token, "GitHub PAT should persist to disk")
    }

    // MARK: - Setting Triggers Save

    func test_settingGithubPAT_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.githubPAT = "ghp_test123"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting GitHub PAT should trigger save notification")
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

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.githubPAT, "", "Missing GitHub PAT should default to empty")
    }

    func test_load_withGitHubPAT() {
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

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.githubPAT, token)
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
        // Change a setting (which in tests flushes synchronously to disk),
        // call flushDebouncedSaveBeforeReloadIfNeeded (no-op since save was immediate),
        // then reload from disk. The new value must survive because it was persisted.
        sut.githubPAT = "ghp_survivetest"

        sut.flushDebouncedSaveBeforeReloadIfNeeded()
        sut.reloadFromDisk()

        XCTAssertEqual(sut.githubPAT, "ghp_survivetest",
                       "githubPAT should survive a reload when it was already flushed to disk")
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
