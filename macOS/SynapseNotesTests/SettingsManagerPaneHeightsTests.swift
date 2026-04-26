import XCTest
@testable import Synapse

/// Tests for SettingsManager sidebar pane height persistence.
/// sidebarPaneHeights stores the proportional height allocation
/// for each pane, keyed by SidebarPane.rawValue.
final class SettingsManagerPaneHeightsTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Default values

    func test_initialState_sidebarPaneHeights_hasDefaults() {
        XCTAssertEqual(sut.sidebarPaneHeights["files"], 400)
        XCTAssertEqual(sut.sidebarPaneHeights["links"], 200)
        XCTAssertEqual(sut.sidebarPaneHeights["terminal"], 300)
        XCTAssertEqual(sut.sidebarPaneHeights["tags"], 200)
    }

    // MARK: - Setting heights

    func test_sidebarPaneHeights_canBeSetForSinglePane() {
        sut.sidebarPaneHeights = ["files": 200]
        XCTAssertEqual(sut.sidebarPaneHeights["files"], 200)
    }

    func test_sidebarPaneHeights_canBeSetForMultiplePanes() {
        sut.sidebarPaneHeights = ["files": 200, "tags": 150, "links": 100]
        XCTAssertEqual(sut.sidebarPaneHeights["files"], 200)
        XCTAssertEqual(sut.sidebarPaneHeights["tags"], 150)
        XCTAssertEqual(sut.sidebarPaneHeights["links"], 100)
    }

    func test_paneHeight_missingKey_returnsNil() {
        sut.sidebarPaneHeights = ["files": 200]
        XCTAssertNil(sut.sidebarPaneHeights["graph"], "Missing key should return nil")
    }

    // MARK: - Persistence

    func test_sidebarPaneHeights_persistToDisk() {
        sut.sidebarPaneHeights = ["files": 250, "tags": 180]
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.sidebarPaneHeights["files"], 250)
        XCTAssertEqual(newManager.sidebarPaneHeights["tags"], 180)
    }

    func test_updatedPaneHeight_persistsNewValue() {
        sut.sidebarPaneHeights["files"] = 100
        sut.sidebarPaneHeights["files"] = 200
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.sidebarPaneHeights["files"], 200)
    }

    func test_missingPaneHeightsInConfig_usesDefaults() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.sidebarPaneHeights["files"], 400, "Missing key should use default")
    }

    // MARK: - Observable changes

    func test_settingSidebarPaneHeights_triggersObjectWillChange() {
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { _ in changeCount += 1 }
        sut.sidebarPaneHeights["files"] = 300
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }
}
