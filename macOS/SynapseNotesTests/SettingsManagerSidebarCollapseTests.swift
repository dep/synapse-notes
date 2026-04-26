import XCTest
@testable import Synapse

/// Tests for SettingsManager sidebar-level collapse: `isSidebarCollapsed(_:)` and
/// `toggleSidebarCollapsed(_:)`.
///
/// These methods operate on `collapsedSidebarIDs` — a set of sidebar UUID strings —
/// and control whether an entire sidebar rail is collapsed into a narrow strip in
/// the UI.  They are distinct from `collapsedPanes`, which tracks whether individual
/// pane sections within a sidebar are open/closed.
///
/// None of this logic was previously covered by the test suite.
final class SettingsManagerSidebarCollapseTests: XCTestCase {

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

    // MARK: - Default state

    func test_isSidebarCollapsed_leftSidebar_defaultsToFalse() {
        XCTAssertFalse(sut.isSidebarCollapsed(FixedSidebar.leftID),
                       "Left sidebar should be expanded by default")
    }

    func test_isSidebarCollapsed_right1Sidebar_defaultsToFalse() {
        XCTAssertFalse(sut.isSidebarCollapsed(FixedSidebar.right1ID),
                       "Right sidebar #1 should be expanded by default")
    }

    func test_isSidebarCollapsed_right2Sidebar_defaultsToTrue() {
        XCTAssertTrue(sut.isSidebarCollapsed(FixedSidebar.right2ID),
                      "Right sidebar #2 (browser) should be collapsed by default")
    }

    // MARK: - toggleSidebarCollapsed — expand → collapse

    func test_toggleSidebarCollapsed_expandedSidebar_collapsesIt() {
        XCTAssertFalse(sut.isSidebarCollapsed(FixedSidebar.leftID), "Precondition: left is expanded")

        sut.toggleSidebarCollapsed(FixedSidebar.leftID)

        XCTAssertTrue(sut.isSidebarCollapsed(FixedSidebar.leftID),
                      "Toggling an expanded sidebar should collapse it")
    }

    // MARK: - toggleSidebarCollapsed — collapse → expand

    func test_toggleSidebarCollapsed_collapsedSidebar_expandsIt() {
        XCTAssertTrue(sut.isSidebarCollapsed(FixedSidebar.right2ID), "Precondition: right2 is collapsed")

        sut.toggleSidebarCollapsed(FixedSidebar.right2ID)

        XCTAssertFalse(sut.isSidebarCollapsed(FixedSidebar.right2ID),
                       "Toggling a collapsed sidebar should expand it")
    }

    // MARK: - Round-trip toggle

    func test_toggleSidebarCollapsed_twice_returnsToOriginalState() {
        let initialState = sut.isSidebarCollapsed(FixedSidebar.leftID)

        sut.toggleSidebarCollapsed(FixedSidebar.leftID)
        sut.toggleSidebarCollapsed(FixedSidebar.leftID)

        XCTAssertEqual(sut.isSidebarCollapsed(FixedSidebar.leftID), initialState,
                       "Two toggles should restore the original collapsed state")
    }

    // MARK: - Independence of sidebars

    func test_toggleSidebarCollapsed_oneSidebar_doesNotAffectOthers() {
        let right1Before = sut.isSidebarCollapsed(FixedSidebar.right1ID)
        let right2Before = sut.isSidebarCollapsed(FixedSidebar.right2ID)

        sut.toggleSidebarCollapsed(FixedSidebar.leftID)

        XCTAssertEqual(sut.isSidebarCollapsed(FixedSidebar.right1ID), right1Before,
                       "Toggling left should not change right1 state")
        XCTAssertEqual(sut.isSidebarCollapsed(FixedSidebar.right2ID), right2Before,
                       "Toggling left should not change right2 state")
    }

    // MARK: - Persistence

    func test_collapsedSidebarIDs_persistAfterToggle() {
        sut.toggleSidebarCollapsed(FixedSidebar.leftID)   // left is now collapsed
        sut.toggleSidebarCollapsed(FixedSidebar.right2ID) // right2 is now expanded

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertTrue(reloaded.isSidebarCollapsed(FixedSidebar.leftID),
                      "Left sidebar collapsed state should persist across restarts")
        XCTAssertFalse(reloaded.isSidebarCollapsed(FixedSidebar.right2ID),
                       "Right2 expanded state should persist across restarts")
    }

    func test_collapsedSidebarIDs_persistRight1Collapse() {
        sut.toggleSidebarCollapsed(FixedSidebar.right1ID)

        let reloaded = SettingsManager(configPath: configFilePath)

        XCTAssertTrue(reloaded.isSidebarCollapsed(FixedSidebar.right1ID),
                      "Right1 collapsed state should survive a settings reload")
    }

    // MARK: - Trigger objectWillChange

    func test_toggleSidebarCollapsed_triggersObjectWillChange() {
        var notified = false
        let cancellable = sut.objectWillChange.sink { notified = true }

        sut.toggleSidebarCollapsed(FixedSidebar.leftID)

        XCTAssertTrue(notified, "toggleSidebarCollapsed should trigger objectWillChange so SwiftUI updates")
        cancellable.cancel()
    }

    // MARK: - isSidebarCollapsed with an unknown UUID

    func test_isSidebarCollapsed_unknownUUID_returnsFalse() {
        let unknownID = UUID()
        XCTAssertFalse(sut.isSidebarCollapsed(unknownID),
                       "An unrecognised sidebar UUID should not be reported as collapsed")
    }
}
