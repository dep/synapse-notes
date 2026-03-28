import XCTest
@testable import Synapse

/// Tests for `sidebarAutoCollapseIDs(forWindowWidth:)` — the pure function that
/// decides which fixed sidebars should be auto-collapsed based on window width.
///
/// Breakpoints (inclusive lower bound):
///   ≥ 1480  → all three sidebars expanded
///   ≥ 1125  → left + right1 expanded; right2 collapsed
///   ≥  900  → left expanded only; right1 + right2 collapsed
///    < 900  → all three sidebars collapsed
///
/// Re-expand follows reverse-cascade: as the window widens past each threshold,
/// the next sidebar in line is restored.
final class SidebarAutoCollapseTests: XCTestCase {

    // MARK: - Helpers

    private func collapsed(at width: CGFloat) -> Set<UUID> {
        sidebarAutoCollapseIDs(forWindowWidth: width)
    }

    // MARK: - All expanded (≥ 1480)

    func test_width1480_noSidebarsCollapsed() {
        XCTAssertTrue(collapsed(at: 1480).isEmpty,
                      "At 1480pt all three sidebars should be expanded")
    }

    func test_width2000_noSidebarsCollapsed() {
        XCTAssertTrue(collapsed(at: 2000).isEmpty,
                      "Wide windows should have all sidebars expanded")
    }

    func test_width1479_right2IsCollapsed() {
        let ids = collapsed(at: 1479)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 1479pt right2 should be collapsed")
        XCTAssertFalse(ids.contains(FixedSidebar.right1ID),
                       "At 1479pt right1 should still be expanded")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 1479pt left should still be expanded")
    }

    // MARK: - Left + right1 only (1125 ..< 1480)

    func test_width1125_right2CollapsedOnly() {
        let ids = collapsed(at: 1125)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID))
        XCTAssertFalse(ids.contains(FixedSidebar.right1ID))
        XCTAssertFalse(ids.contains(FixedSidebar.leftID))
    }

    func test_width1300_right2CollapsedOnly() {
        let ids = collapsed(at: 1300)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID))
        XCTAssertFalse(ids.contains(FixedSidebar.right1ID))
        XCTAssertFalse(ids.contains(FixedSidebar.leftID))
    }

    func test_width1124_right1AndRight2Collapsed() {
        let ids = collapsed(at: 1124)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 1124pt right2 should be collapsed")
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID),
                      "At 1124pt right1 should be collapsed")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 1124pt left should still be expanded")
    }

    // MARK: - Left only (900 ..< 1125)

    func test_width900_right1AndRight2Collapsed() {
        let ids = collapsed(at: 900)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID))
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID))
        XCTAssertFalse(ids.contains(FixedSidebar.leftID))
    }

    func test_width1000_right1AndRight2Collapsed() {
        let ids = collapsed(at: 1000)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID))
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID))
        XCTAssertFalse(ids.contains(FixedSidebar.leftID))
    }

    func test_width899_allThreeCollapsed() {
        let ids = collapsed(at: 899)
        XCTAssertTrue(ids.contains(FixedSidebar.leftID),
                      "At 899pt left should be collapsed")
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID),
                      "At 899pt right1 should be collapsed")
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 899pt right2 should be collapsed")
    }

    // MARK: - All collapsed (< 900)

    func test_width600_allCollapsed() {
        let ids = collapsed(at: 600)
        XCTAssertEqual(ids, [FixedSidebar.leftID, FixedSidebar.right1ID, FixedSidebar.right2ID])
    }

    func test_width0_allCollapsed() {
        let ids = collapsed(at: 0)
        XCTAssertEqual(ids, [FixedSidebar.leftID, FixedSidebar.right1ID, FixedSidebar.right2ID])
    }

    // MARK: - Exact boundary values

    func test_exactBoundary1480_noneCollapsed() {
        XCTAssertTrue(collapsed(at: 1480).isEmpty)
    }

    func test_exactBoundary1125_right2Only() {
        let ids = collapsed(at: 1125)
        XCTAssertEqual(ids, [FixedSidebar.right2ID])
    }

    func test_exactBoundary900_right1AndRight2() {
        let ids = collapsed(at: 900)
        XCTAssertEqual(ids, [FixedSidebar.right1ID, FixedSidebar.right2ID])
    }

    // MARK: - Return type is a Set<UUID> (not UUIDStrings)

    func test_returnType_containsUUIDs() {
        let ids = collapsed(at: 500)
        XCTAssertTrue(ids is Set<UUID>)
    }
}
