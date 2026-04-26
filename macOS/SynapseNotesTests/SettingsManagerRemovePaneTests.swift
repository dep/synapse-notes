import XCTest
@testable import Synapse

/// Tests for `SettingsManager.removePane(_:fromSidebar:)` and
/// `SettingsManager.removePaneItem(_:fromSidebar:)`.
///
/// These are the deletion paths for sidebar panes.  `removePane` targets built-in
/// panes by type; `removePaneItem` targets any `SidebarPaneItem` (including note
/// panes) by value equality.  Both were previously untested.
final class SettingsManagerRemovePaneTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        sut = SettingsManager(configPath: tempDir.appendingPathComponent("settings.json").path)
        // Default layout: left=[files, links], right1=[terminal, tags], right2=[browser]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - removePane(_:fromSidebar:)

    func test_removePane_removesBuiltInPaneFromCorrectSidebar() {
        sut.removePane(.files, fromSidebar: FixedSidebar.leftID)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertFalse(left.panes.contains(.files),
                       "files pane should be removed from the left sidebar")
    }

    func test_removePane_leavesOtherPanesInSidebar_intact() {
        sut.removePane(.files, fromSidebar: FixedSidebar.leftID)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertTrue(left.panes.contains(.links),
                      "links pane should remain after removing files")
    }

    func test_removePane_doesNotAffectOtherSidebars() {
        sut.removePane(.files, fromSidebar: FixedSidebar.leftID)

        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertTrue(right1.panes.contains(.terminal),
                      "Removing from left sidebar should not touch right1 sidebar")
    }

    func test_removePane_withWrongSidebarID_doesNothing() {
        // 'files' lives in the left sidebar; trying to remove it from right1 should no-op.
        let leftBefore = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes

        sut.removePane(.files, fromSidebar: FixedSidebar.right1ID)

        let leftAfter = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes
        XCTAssertEqual(leftBefore, leftAfter,
                       "Removing a pane from the wrong sidebar should be a no-op for all sidebars")
    }

    func test_removePane_paneNotInSidebar_doesNothing() {
        // 'browser' is in right2, not left; removing it from left should be a no-op.
        let leftBefore = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes

        sut.removePane(.browser, fromSidebar: FixedSidebar.leftID)

        let leftAfter = sut.sidebars.first { $0.id == FixedSidebar.leftID }!.panes
        XCTAssertEqual(leftBefore, leftAfter,
                       "Removing a pane that isn't in the sidebar should be a no-op")
    }

    func test_removePane_canEmptySidebar() {
        // right2 has a single pane (browser); removing it should leave an empty sidebar.
        sut.removePane(.browser, fromSidebar: FixedSidebar.right2ID)

        let right2 = sut.sidebars.first { $0.id == FixedSidebar.right2ID }!
        XCTAssertTrue(right2.panes.isEmpty,
                      "Removing the only pane should leave the sidebar empty")
    }

    // MARK: - removePaneItem(_:fromSidebar:)

    func test_removePaneItem_removesBuiltInItem() {
        sut.removePaneItem(.builtIn(.terminal), fromSidebar: FixedSidebar.right1ID)

        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertFalse(right1.panes.contains(.terminal),
                       "removePaneItem should remove the matching built-in item")
    }

    func test_removePaneItem_leavesOtherItemsUntouched() {
        sut.removePaneItem(.builtIn(.terminal), fromSidebar: FixedSidebar.right1ID)

        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }!
        XCTAssertTrue(right1.panes.contains(.tags),
                      "tags pane should remain after removing terminal")
    }

    func test_removePaneItem_forNotePane_removesCorrectItem() {
        let noteFile = tempDir.appendingPathComponent("pinned.md")
        try! "# Pinned".write(to: noteFile, atomically: true, encoding: .utf8)

        // Insert a note pane, then remove it by value.
        sut.insertNotePane(fileURL: noteFile, toSidebar: FixedSidebar.leftID)
        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        guard let insertedItem = left.panes.last else {
            XCTFail("Note pane was not inserted"); return
        }
        let countAfterInsert = left.panes.count

        sut.removePaneItem(insertedItem, fromSidebar: FixedSidebar.leftID)

        let leftAfter = sut.sidebars.first { $0.id == FixedSidebar.leftID }!
        XCTAssertEqual(leftAfter.panes.count, countAfterInsert - 1,
                       "Removing the note pane by item value should decrease the count by 1")
        XCTAssertFalse(leftAfter.panes.contains(insertedItem),
                       "The removed note pane should no longer be present")
    }

    func test_removePaneItem_unknownSidebarID_doesNothing() {
        let totalBefore = sut.sidebars.flatMap(\.panes).count

        sut.removePaneItem(.builtIn(.files), fromSidebar: UUID())

        let totalAfter = sut.sidebars.flatMap(\.panes).count
        XCTAssertEqual(totalBefore, totalAfter,
                       "removePaneItem with an unknown sidebar ID should leave everything unchanged")
    }

    func test_removePaneItem_doesNotAffectSiblingItem_withSamePane_inOtherSidebar() {
        // Even if the same pane type appears in multiple sidebars (unusual but possible after
        // manual config edits), removePaneItem on one sidebar must not touch the other.
        sut.assignPane(.files, toSidebar: FixedSidebar.right2ID)
        // Now files is in right2; left sidebar should have had files removed by assignPane.
        // Re-add files to left so both sidebars have it.
        sut.sidebars = sut.sidebars.map { sidebar in
            if sidebar.id == FixedSidebar.leftID {
                var s = sidebar; s.panes.insert(.builtIn(.files), at: 0); return s
            }
            return sidebar
        }

        sut.removePaneItem(.builtIn(.files), fromSidebar: FixedSidebar.leftID)

        let right2 = sut.sidebars.first { $0.id == FixedSidebar.right2ID }!
        XCTAssertTrue(right2.panes.contains(.files),
                      "removePaneItem should only remove from the specified sidebar, not others")
    }
}
