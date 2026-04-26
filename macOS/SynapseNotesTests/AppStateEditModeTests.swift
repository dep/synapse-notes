import XCTest
@testable import Synapse

/// Tests for AppState.isEditMode — its initialization from settings and bidirectional sync.
final class AppStateEditModeTests: XCTestCase {
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("Synapse-settings.json").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeSettings(defaultEditMode: Bool, hideMarkdown: Bool = false) -> SettingsManager {
        let s = SettingsManager(configPath: configFilePath)
        s.defaultEditMode = defaultEditMode
        s.hideMarkdownWhileEditing = hideMarkdown
        return s
    }

    // MARK: - Initialization from settings

    func test_isEditMode_initializesTrue_whenDefaultEditModeIsTrue() {
        let settings = makeSettings(defaultEditMode: true)
        let appState = AppState(settings: settings)

        XCTAssertTrue(appState.isEditMode, "isEditMode should be true when settings.defaultEditMode is true")
    }

    func test_isEditMode_initializesFalse_whenDefaultEditModeIsFalse() {
        let settings = makeSettings(defaultEditMode: false)
        let appState = AppState(settings: settings)

        XCTAssertFalse(appState.isEditMode, "isEditMode should be false when settings.defaultEditMode is false")
    }

    // MARK: - Bidirectional sync

    func test_isEditMode_change_writesBackToSettings() {
        let settings = makeSettings(defaultEditMode: true)
        let appState = AppState(settings: settings)

        appState.isEditMode = false

        XCTAssertFalse(appState.settings.defaultEditMode, "Changing isEditMode should write back to settings.defaultEditMode")
    }

    func test_isEditMode_toggleBackToTrue_updatesSettings() {
        let settings = makeSettings(defaultEditMode: false)
        let appState = AppState(settings: settings)

        appState.isEditMode = true

        XCTAssertTrue(appState.settings.defaultEditMode)
    }

    func test_isEditMode_persistsAcrossNewAppState_viaSettings() {
        // Simulate: user sets view mode, quits, relaunches.
        let settings = makeSettings(defaultEditMode: true)
        let appState = AppState(settings: settings)
        appState.isEditMode = false
        // settings.defaultEditMode is now false — simulate save/reload.
        let reloadedSettings = SettingsManager(configPath: configFilePath)
        let relaunchedAppState = AppState(settings: reloadedSettings)

        XCTAssertFalse(relaunchedAppState.isEditMode, "isEditMode should restore as false after quit/relaunch")
    }

    func test_enablingHideMarkdownWhileEditing_forcesEditMode() {
        let settings = makeSettings(defaultEditMode: false, hideMarkdown: false)
        let appState = AppState(settings: settings)

        XCTAssertFalse(appState.isEditMode, "Precondition: app starts in view mode")

        settings.hideMarkdownWhileEditing = true

        XCTAssertTrue(
            appState.isEditMode,
            "Enabling hide-markdown mode must force edit mode so the editor does not become read-only with no toggle"
        )
    }

    func test_hideMarkdownWhileEditing_forcesEditModeOnInit() {
        let settings = makeSettings(defaultEditMode: false, hideMarkdown: true)
        let appState = AppState(settings: settings)

        XCTAssertTrue(
            appState.isEditMode,
            "When hide-markdown mode is enabled, app must start in edit mode"
        )
    }
}
