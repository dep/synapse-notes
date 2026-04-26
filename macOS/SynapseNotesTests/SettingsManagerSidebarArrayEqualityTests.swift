import XCTest
@testable import Synapse

/// Ensures `[SidebarPaneItem]` can be compared to `[SidebarPane]` — used when persisting
/// and diffing sidebar layout state.
final class SettingsManagerSidebarArrayEqualityTests: XCTestCase {

    func test_itemsEqualPanes_whenAllBuiltInMatch() {
        let items: [SidebarPaneItem] = [.builtIn(.files), .builtIn(.calendar), .builtIn(.tags)]
        let panes: [SidebarPane] = [.files, .calendar, .tags]
        XCTAssertTrue(items == panes)
        XCTAssertTrue(panes == items)
    }

    func test_itemsNotEqualPanes_whenOrderDiffers() {
        let items: [SidebarPaneItem] = [.builtIn(.files), .builtIn(.tags)]
        let panes: [SidebarPane] = [.tags, .files]
        XCTAssertFalse(items == panes)
    }

    func test_itemsNotEqualPanes_whenNotePanePresent() {
        let note = SidebarNotePane(fileURL: URL(fileURLWithPath: "/tmp/note.md"))
        let items: [SidebarPaneItem] = [.builtIn(.files), .note(note)]
        let panes: [SidebarPane] = [.files]
        XCTAssertFalse(items == panes)
    }

    func test_emptyArraysAreEqual() {
        let items: [SidebarPaneItem] = []
        let panes: [SidebarPane] = []
        XCTAssertTrue(items == panes)
    }
}
