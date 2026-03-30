import XCTest
@testable import Synapse

/// Tests for `sidebarAutoCollapseIDs(forWindowWidth:)` — the pure function that
/// decides which fixed sidebars should be auto-collapsed based on window width.
///
/// Breakpoints use phi-based calculations (phi ≈ 1.618):
///   ≥ 1294  → all three sidebars expanded  (800 * phi)
///   ≥ 970   → left + right1 expanded; right2 collapsed  (600 * phi)
///   ≥ 809   → left expanded only; right1 + right2 collapsed  (500 * phi)
///    < 809  → all three sidebars collapsed
///
/// Re-expand follows reverse-cascade: as the window widens past each threshold,
/// the next sidebar in line is restored.
final class SidebarAutoCollapseTests: XCTestCase {

    // MARK: - Helpers

    private func collapsed(at width: CGFloat) -> Set<UUID> {
        sidebarAutoCollapseIDs(forWindowWidth: width)
    }

    // MARK: - All expanded (≥ 1294)

    func test_width1400_noSidebarsCollapsed() {
        XCTAssertTrue(collapsed(at: 1400).isEmpty,
                      "At 1400pt all three sidebars should be expanded (threshold is ~1294)")
    }

    func test_width2000_noSidebarsCollapsed() {
        XCTAssertTrue(collapsed(at: 2000).isEmpty,
                      "Wide windows should have all sidebars expanded")
    }

    func test_width1293_right2IsCollapsed() {
        let ids = collapsed(at: 1293)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 1293pt right2 should be collapsed (threshold is ~1294)")
        XCTAssertFalse(ids.contains(FixedSidebar.right1ID),
                       "At 1293pt right1 should still be expanded")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 1293pt left should still be expanded")
    }

    // MARK: - Left + right1 only (970 ..< 1294)

    func test_width1100_right2CollapsedOnly() {
        let ids = collapsed(at: 1100)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 1100pt right2 should be collapsed (threshold is ~970)")
        XCTAssertFalse(ids.contains(FixedSidebar.right1ID),
                       "At 1100pt right1 should still be expanded")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 1100pt left should still be expanded")
    }

    func test_width969_right1AndRight2Collapsed() {
        let ids = collapsed(at: 969)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 969pt right2 should be collapsed (threshold is ~970)")
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID),
                      "At 969pt right1 should be collapsed (threshold is ~970)")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 969pt left should still be expanded")
    }

    // MARK: - Left only (809 ..< 970)

    func test_width850_right1AndRight2Collapsed() {
        let ids = collapsed(at: 850)
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 850pt right2 should be collapsed (threshold is ~809)")
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID),
                      "At 850pt right1 should be collapsed (threshold is ~809)")
        XCTAssertFalse(ids.contains(FixedSidebar.leftID),
                       "At 850pt left should still be expanded")
    }

    func test_width808_allThreeCollapsed() {
        let ids = collapsed(at: 808)
        XCTAssertTrue(ids.contains(FixedSidebar.leftID),
                      "At 808pt left should be collapsed (threshold is ~809)")
        XCTAssertTrue(ids.contains(FixedSidebar.right1ID),
                      "At 808pt right1 should be collapsed (threshold is ~809)")
        XCTAssertTrue(ids.contains(FixedSidebar.right2ID),
                      "At 808pt right2 should be collapsed (threshold is ~809)")
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

    func test_exactBoundary1295_allExpanded() {
        // At 1295 (just above 800 * phi ≈ 1294.43), all sidebars should be expanded
        XCTAssertTrue(collapsed(at: 1295).isEmpty)
    }

    func test_exactBoundary971_right2Collapsed() {
        // At 971 (just above 600 * phi ≈ 970.82), only right2 should be collapsed
        let ids = collapsed(at: 971)
        XCTAssertEqual(ids, [FixedSidebar.right2ID])
    }

    func test_exactBoundary810_right1AndRight2Collapsed() {
        // At 810 (just above 500 * phi ≈ 809.02), right1 and right2 should be collapsed
        let ids = collapsed(at: 810)
        XCTAssertEqual(ids, [FixedSidebar.right1ID, FixedSidebar.right2ID])
    }

    // MARK: - Return type is a Set<UUID> (not UUIDStrings)

    func test_returnType_containsUUIDs() {
        let ids = collapsed(at: 500)
        XCTAssertTrue(ids is Set<UUID>)
    }
}
