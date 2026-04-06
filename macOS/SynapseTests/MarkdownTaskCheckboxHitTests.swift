import XCTest
@testable import Synapse

/// Tests `MarkdownTaskCheckboxHit.replacement` — the exact string applied when toggling task markers in the editor.
final class MarkdownTaskCheckboxHitTests: XCTestCase {

    func test_replacement_uncheckedTogglesToCheckedMarker() {
        let hit = MarkdownTaskCheckboxHit(
            itemRange: NSRange(location: 0, length: 10),
            markerRange: NSRange(location: 2, length: 3),
            isChecked: false
        )
        XCTAssertEqual(hit.replacement, "[x]")
    }

    func test_replacement_checkedTogglesToUncheckedMarker() {
        let hit = MarkdownTaskCheckboxHit(
            itemRange: NSRange(location: 0, length: 10),
            markerRange: NSRange(location: 2, length: 3),
            isChecked: true
        )
        XCTAssertEqual(hit.replacement, "[ ]")
    }

    func test_hit_equatable_sameRangesAndCheckedMatch() {
        let a = MarkdownTaskCheckboxHit(itemRange: NSRange(location: 0, length: 5), markerRange: NSRange(location: 2, length: 3), isChecked: false)
        let b = MarkdownTaskCheckboxHit(itemRange: NSRange(location: 0, length: 5), markerRange: NSRange(location: 2, length: 3), isChecked: false)
        XCTAssertEqual(a, b)
    }

    func test_hit_equatable_differentChecked_notEqual() {
        let a = MarkdownTaskCheckboxHit(itemRange: NSRange(location: 0, length: 5), markerRange: NSRange(location: 2, length: 3), isChecked: false)
        let b = MarkdownTaskCheckboxHit(itemRange: NSRange(location: 0, length: 5), markerRange: NSRange(location: 2, length: 3), isChecked: true)
        XCTAssertNotEqual(a, b)
    }
}
