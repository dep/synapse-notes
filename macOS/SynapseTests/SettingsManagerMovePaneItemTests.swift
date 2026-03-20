import XCTest
@testable import Synapse

/// Tests for `SettingsManager.movePaneItem(_:toSidebar:at:)` and the convenience
/// wrapper `movePane(_:toSidebar:at:)`.
///
/// The `movePaneItem` implementation contains a subtle `removedFromSameSidebarBeforeTarget`
/// index correction that is easy to get wrong and causes drag-and-drop reordering to
/// appear to "jump" one position when moving an item downward within the same sidebar.
/// This was previously completely untested.
final class SettingsManagerMovePaneItemTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        sut = SettingsManager(configPath: tempDir.appendingPathComponent("settings.json").path)

        // Start with a predictable layout:
        //   left:   [files, links]
        //   right1: [terminal, tags]
        //   right2: [browser]
        // (These are the FixedSidebar defaults, already set by SettingsManager.init.)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Cross-sidebar moves

    func test_movePane_fromLeft_toRight1_removesFromLeft() {
        sut.movePane(.files, toSidebar: FixedSidebar.right1ID, at: 0)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertFalse(left.panes.contains(.files),
                       "files pane should be removed from the left sidebar")
    }

    func test_movePane_fromLeft_toRight1_addsToRight1() {
        sut.movePane(.files, toSidebar: FixedSidebar.right1ID, at: 0)

        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertTrue(right1.panes.contains(.files),
                      "files pane should appear in the right1 sidebar after the move")
    }

    func test_movePane_crossSidebar_insertsAtCorrectIndex() {
        // right1 currently has [terminal, tags]; inserting files at index 1 → [terminal, files, tags]
        sut.movePane(.files, toSidebar: FixedSidebar.right1ID, at: 1)

        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertEqual(right1.panes[1].builtInPane, .files,
                       "files should appear at index 1 after cross-sidebar move")
    }

    func test_movePane_crossSidebar_doesNotDuplicateItem() {
        sut.movePane(.files, toSidebar: FixedSidebar.right1ID, at: 0)

        let allPanes = sut.sidebars.flatMap(\.panes)
        let filesCount = allPanes.filter { $0.builtInPane == .files }.count
        XCTAssertEqual(filesCount, 1, "files pane should appear exactly once after a move")
    }

    // MARK: - Same-sidebar moves (reordering)

    func test_movePaneItem_withinSameSidebar_movingDown_adjustsIndex() {
        // left sidebar starts as [files, links].
        // Moving 'files' (index 0) to index 2 (after 'links') should produce [links, files].
        sut.movePaneItem(.builtIn(.files), toSidebar: FixedSidebar.leftID, at: 2)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertEqual(left.panes.compactMap(\.builtInPane), [.links, .files],
                       "Moving down within same sidebar should correctly reorder to [links, files]")
    }

    func test_movePaneItem_withinSameSidebar_movingUp_correctOrder() {
        // left sidebar: [files, links].
        // Moving 'links' (index 1) to index 0 should produce [links, files].
        sut.movePaneItem(.builtIn(.links), toSidebar: FixedSidebar.leftID, at: 0)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertEqual(left.panes.compactMap(\.builtInPane), [.links, .files],
                       "Moving up within same sidebar should produce [links, files]")
    }

    func test_movePaneItem_withinSameSidebar_sameSamePosition_noChange() {
        // Moving 'files' to index 0 when it's already at index 0 should be a no-op.
        let before = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes

        sut.movePaneItem(.builtIn(.files), toSidebar: FixedSidebar.leftID, at: 0)

        let after = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes
        XCTAssertEqual(before, after, "Moving an item to its current position should be a no-op")
    }

    // MARK: - Move a non-existent item (should append to target)

    func test_movePaneItem_itemNotCurrentlyInAnySidebar_appendsToTarget() {
        // 'graph' is not in any sidebar by default; moving it to left should add it.
        // (assignPane/movePane is the API for panes not yet in the layout.)
        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        let countBefore = left.panes.count

        sut.movePaneItem(.builtIn(.graph), toSidebar: FixedSidebar.leftID, at: 0)

        let leftAfter = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertEqual(leftAfter.panes.count, countBefore + 1,
                       "Moving a pane not yet in any sidebar should insert it")
        XCTAssertEqual(leftAfter.panes.first?.builtInPane, .graph)
    }

    // MARK: - Pane count invariant after move

    func test_movePane_crossSidebar_totalPaneCountUnchanged() {
        let totalBefore = sut.sidebars.flatMap(\.panes).count

        sut.movePane(.files, toSidebar: FixedSidebar.right1ID, at: 0)

        let totalAfter = sut.sidebars.flatMap(\.panes).count
        XCTAssertEqual(totalBefore, totalAfter,
                       "A cross-sidebar move should not change the total number of panes")
    }

    // MARK: - Convenience movePane wrapper

    func test_movePane_convenience_delegatesToMovePaneItem() {
        // movePane is just a convenience wrapper; verify it produces the same outcome.
        sut.movePane(.terminal, toSidebar: FixedSidebar.leftID, at: 0)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertTrue(left.panes.contains(.terminal),
                      "movePane convenience wrapper should move the pane via movePaneItem")
    }
}
