import XCTest
@testable import Synapse

/// Tests for SettingsManager: collapsedPanes and pane-height persistence.
final class SettingsManagerCollapsedPanesTests: XCTestCase {

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

    // MARK: - collapsedPanes defaults

    func test_collapsedPanes_defaultsToEmpty() {
        XCTAssertTrue(sut.collapsedPanes.isEmpty, "collapsedPanes should default to an empty set")
    }

    // MARK: - collapsedPanes mutations

    func test_collapsedPanes_insertPersists() {
        sut.collapsedPanes.insert(SidebarPane.files.rawValue)
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(reloaded.collapsedPanes.contains(SidebarPane.files.rawValue))
    }

    func test_collapsedPanes_removePerissts() {
        sut.collapsedPanes.insert(SidebarPane.tags.rawValue)
        sut.collapsedPanes.insert(SidebarPane.links.rawValue)
        sut.collapsedPanes.remove(SidebarPane.tags.rawValue)
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertFalse(reloaded.collapsedPanes.contains(SidebarPane.tags.rawValue))
        XCTAssertTrue(reloaded.collapsedPanes.contains(SidebarPane.links.rawValue))
    }

    func test_collapsedPanes_multipleValuesPersist() {
        sut.collapsedPanes = [SidebarPane.files.rawValue, SidebarPane.terminal.rawValue]
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.collapsedPanes, [SidebarPane.files.rawValue, SidebarPane.terminal.rawValue])
    }

    func test_collapsedPanes_clearingPersists() {
        sut.collapsedPanes = [SidebarPane.files.rawValue]
        sut.collapsedPanes = []
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(reloaded.collapsedPanes.isEmpty)
    }

    // MARK: - collapsedPanes JSON fallback

    func test_collapsedPanes_missingKeyInJSON_defaultsToEmpty() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertTrue(reloaded.collapsedPanes.isEmpty, "Missing collapsedPanes key should default to empty set")
    }

    // MARK: - sidebarPaneHeights persistence

    func test_sidebarPaneHeights_setValuePersists() {
        sut.sidebarPaneHeights[SidebarPane.files.rawValue] = 200
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.sidebarPaneHeights[SidebarPane.files.rawValue], 200)
    }

    func test_sidebarPaneHeights_updateValuePersists() {
        sut.sidebarPaneHeights[SidebarPane.files.rawValue] = 100
        sut.sidebarPaneHeights[SidebarPane.files.rawValue] = 250
        let reloaded = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(reloaded.sidebarPaneHeights[SidebarPane.files.rawValue], 250)
    }

    // MARK: - Change notifications

    func test_collapsedPanes_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }
        sut.collapsedPanes.insert("files")
        XCTAssertGreaterThanOrEqual(notifyCount, 1)
        cancellable.cancel()
    }

    func test_sidebarPaneHeights_triggersSaveNotification() {
        var notifyCount = 0
        let cancellable = sut.objectWillChange.sink { _ in notifyCount += 1 }
        sut.sidebarPaneHeights["files"] = 100
        XCTAssertGreaterThanOrEqual(notifyCount, 1)
        cancellable.cancel()
    }
}
