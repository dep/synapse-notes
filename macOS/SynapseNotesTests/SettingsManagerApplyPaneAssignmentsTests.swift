import XCTest
@testable import Synapse

/// Tests for `SettingsManager.applyPaneAssignments(_:)` — the static factory that
/// maps a saved pane-assignment dictionary onto the three fixed sidebar slots.
///
/// This method is the bridge between the YAML-persisted sidebar layout and the
/// runtime `sidebars` array.  If it regresses, all users lose their sidebar
/// customisations on every restart.  It was not previously covered by the test
/// suite.
final class SettingsManagerApplyPaneAssignmentsTests: XCTestCase {

    // MARK: - nil input → defaults

    func test_applyPaneAssignments_nil_returnsFixedSidebarDefaults() {
        let result = SettingsManager.applyPaneAssignments(nil)

        XCTAssertEqual(result.count, 3, "Should always return exactly 3 sidebars")
        XCTAssertEqual(result[0].id, FixedSidebar.leftID)
        XCTAssertEqual(result[1].id, FixedSidebar.right1ID)
        XCTAssertEqual(result[2].id, FixedSidebar.right2ID)
    }

    func test_applyPaneAssignments_nil_leftSidebarHasDefaultPanes() {
        let result = SettingsManager.applyPaneAssignments(nil)
        let left = result.first { $0.id == FixedSidebar.leftID }!

        XCTAssertTrue(left.panes.contains(.files))
        XCTAssertTrue(left.panes.contains(.links))
    }

    func test_applyPaneAssignments_nil_right1HasDefaultPanes() {
        let result = SettingsManager.applyPaneAssignments(nil)
        let right1 = result.first { $0.id == FixedSidebar.right1ID }!

        XCTAssertTrue(right1.panes.contains(.terminal))
        XCTAssertTrue(right1.panes.contains(.tags))
    }

    func test_applyPaneAssignments_nil_right2HasDefaultPanes() {
        let result = SettingsManager.applyPaneAssignments(nil)
        let right2 = result.first { $0.id == FixedSidebar.right2ID }!

        XCTAssertEqual(right2.panes, [.builtIn(.browser)])
    }

    // MARK: - Partial override — only one sidebar remapped

    func test_applyPaneAssignments_partialOverride_updatesOnlySpecifiedSidebar() {
        let assignments: [String: [SidebarPaneItem]] = [
            FixedSidebar.leftID.uuidString: [.builtIn(.files), .builtIn(.tags)]
        ]

        let result = SettingsManager.applyPaneAssignments(assignments)

        let left = result.first { $0.id == FixedSidebar.leftID }!
        XCTAssertEqual(left.panes, [.builtIn(.files), .builtIn(.tags)],
                       "Left sidebar should use the provided assignment")

        let right1 = result.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertTrue(right1.panes.contains(.terminal),
                      "Unspecified sidebars should fall back to their defaults")
    }

    // MARK: - Full override

    func test_applyPaneAssignments_fullOverride_appliesAllSidebars() {
        let assignments: [String: [SidebarPaneItem]] = [
            FixedSidebar.leftID.uuidString:   [.builtIn(.graph)],
            FixedSidebar.right1ID.uuidString: [.builtIn(.browser), .builtIn(.links)],
            FixedSidebar.right2ID.uuidString: [.builtIn(.files), .builtIn(.terminal), .builtIn(.tags)]
        ]

        let result = SettingsManager.applyPaneAssignments(assignments)

        let left   = result.first { $0.id == FixedSidebar.leftID }!
        let right1 = result.first { $0.id == FixedSidebar.right1ID }!
        let right2 = result.first { $0.id == FixedSidebar.right2ID }!

        XCTAssertEqual(left.panes,   [.builtIn(.graph)])
        XCTAssertEqual(right1.panes, [.builtIn(.browser), .builtIn(.links)])
        XCTAssertEqual(right2.panes, [.builtIn(.files), .builtIn(.terminal), .builtIn(.tags)])
    }

    // MARK: - Empty pane list is valid

    func test_applyPaneAssignments_emptyPaneList_producesEmptySidebar() {
        let assignments: [String: [SidebarPaneItem]] = [
            FixedSidebar.leftID.uuidString: []
        ]

        let result = SettingsManager.applyPaneAssignments(assignments)
        let left = result.first { $0.id == FixedSidebar.leftID }!

        XCTAssertTrue(left.panes.isEmpty, "An explicit empty list should produce a sidebar with no panes")
    }

    // MARK: - Unknown sidebar key is ignored

    func test_applyPaneAssignments_unknownKey_isIgnored() {
        let bogusKey = UUID().uuidString
        let assignments: [String: [SidebarPaneItem]] = [
            bogusKey: [.builtIn(.graph), .builtIn(.browser)]
        ]

        let result = SettingsManager.applyPaneAssignments(assignments)

        // All three fixed sidebars should still exist with their defaults.
        XCTAssertEqual(result.count, 3)
        let left = result.first { $0.id == FixedSidebar.leftID }!
        XCTAssertTrue(left.panes.contains(.files),
                      "An unrecognised key should not disturb the fixed sidebar defaults")
    }

    // MARK: - Sidebar positions are preserved

    func test_applyPaneAssignments_leftSidebar_positionIsLeft() {
        let result = SettingsManager.applyPaneAssignments(nil)
        let left = result.first { $0.id == FixedSidebar.leftID }!

        XCTAssertEqual(left.position, .left)
    }

    func test_applyPaneAssignments_rightSidebars_positionIsRight() {
        let result = SettingsManager.applyPaneAssignments(nil)

        for sidebar in result where sidebar.id != FixedSidebar.leftID {
            XCTAssertEqual(sidebar.position, .right,
                           "Right sidebars should retain their position after assignment")
        }
    }

    // MARK: - Order of sidebars in the result

    func test_applyPaneAssignments_sidebarOrder_matchesFixedSidebarAll() {
        let result = SettingsManager.applyPaneAssignments(nil)
        let expectedIDs = FixedSidebar.all.map(\.id)
        let actualIDs   = result.map(\.id)

        XCTAssertEqual(actualIDs, expectedIDs,
                       "applyPaneAssignments should preserve the canonical sidebar order")
    }
}
