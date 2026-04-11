import XCTest
@testable import Synapse

/// Tests for `MarkdownTaskCheckboxHit` — drives checkbox toggle text replacement in the editor.
final class MarkdownTaskCheckboxHitTests: XCTestCase {

    func test_replacement_uncheckedTogglesToCheckedToken() {
        let hit = MarkdownTaskCheckboxHit(
            markerRange: NSRange(location: 2, length: 3),
            isChecked: false
        )
        XCTAssertEqual(hit.replacement, "[x]")
    }

    func test_replacement_checkedTogglesToUncheckedToken() {
        let hit = MarkdownTaskCheckboxHit(
            markerRange: NSRange(location: 2, length: 3),
            isChecked: true
        )
        XCTAssertEqual(hit.replacement, "[ ]")
    }

    func test_equatable_sameValuesAreEqual() {
        let a = MarkdownTaskCheckboxHit(markerRange: NSRange(location: 2, length: 3), isChecked: false)
        let b = MarkdownTaskCheckboxHit(markerRange: NSRange(location: 2, length: 3), isChecked: false)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentCheckedStateNotEqual() {
        let a = MarkdownTaskCheckboxHit(markerRange: NSRange(location: 2, length: 3), isChecked: false)
        let b = MarkdownTaskCheckboxHit(markerRange: NSRange(location: 2, length: 3), isChecked: true)
        XCTAssertNotEqual(a, b)
    }
}
