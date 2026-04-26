import XCTest
import AppKit
@testable import Synapse

/// Tests for `ThemeEnvironment.observe(_:)` wiring — keeps `theme` in sync with `SettingsManager.activeTheme`.
@MainActor
final class ThemeEnvironmentTests: XCTestCase {

    private var tempDir: URL!
    private var configPath: String!
    private var settings: SettingsManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configPath = tempDir.appendingPathComponent("theme-env-test.json").path
        settings = SettingsManager(configPath: configPath)
    }

    override func tearDown() {
        settings = nil
        try? FileManager.default.removeItem(at: tempDir)
        ThemeEnvironment.shared = nil
        super.tearDown()
    }

    func test_observe_setsThemeFromSettingsImmediately() {
        settings.activeThemeName = "Synapse (Light)"
        let env = ThemeEnvironment()
        env.observe(settings)

        XCTAssertEqual(env.theme.name, "Synapse (Light)")
    }

    func test_observe_updatesThemeWhenActiveThemeNameChanges() {
        let env = ThemeEnvironment()
        env.observe(settings)

        settings.activeThemeName = "Dracula (Dark)"

        let deadline = Date().addingTimeInterval(1.0)
        while env.theme.name != "Dracula (Dark)", Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(env.theme.name, "Dracula (Dark)")
    }

    func test_isLightTheme_trueForSynapseLight() {
        settings.activeThemeName = "Synapse (Light)"
        let env = ThemeEnvironment()
        env.observe(settings)

        XCTAssertTrue(env.isLightTheme)
    }

    func test_isLightTheme_falseForSynapseDark() {
        settings.activeThemeName = "Synapse (Dark)"
        let env = ThemeEnvironment()
        env.observe(settings)

        XCTAssertFalse(env.isLightTheme)
    }

    func test_nsAppearance_matchesLightVersusDarkTheme() {
        settings.activeThemeName = "Synapse (Light)"
        let lightEnv = ThemeEnvironment()
        lightEnv.observe(settings)
        XCTAssertEqual(lightEnv.nsAppearance.name, NSAppearance.Name.aqua)

        settings.activeThemeName = "Synapse (Dark)"
        let darkEnv = ThemeEnvironment()
        darkEnv.observe(settings)
        XCTAssertEqual(darkEnv.nsAppearance.name, NSAppearance.Name.darkAqua)
    }
}
