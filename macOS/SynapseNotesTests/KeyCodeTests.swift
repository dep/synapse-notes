import XCTest
@testable import Synapse

/// Tests for KeyCode virtual key constants.
///
/// KeyCode values drive every keyboard shortcut in the app (modal navigation,
/// Escape-to-close, arrow-key selection, Return-to-confirm).  The values are
/// macOS-platform constants that must never drift — a wrong value silently
/// breaks keyboard-driven workflows for all users.
final class KeyCodeTests: XCTestCase {

    // MARK: - Navigation keys

    func test_downArrow_is125() {
        XCTAssertEqual(KeyCode.downArrow, 125,
                       "Down-arrow virtual key code must be 125")
    }

    func test_upArrow_is126() {
        XCTAssertEqual(KeyCode.upArrow, 126,
                       "Up-arrow virtual key code must be 126")
    }

    func test_leftArrow_is123() {
        XCTAssertEqual(KeyCode.leftArrow, 123,
                       "Left-arrow virtual key code must be 123")
    }

    func test_rightArrow_is124() {
        XCTAssertEqual(KeyCode.rightArrow, 124,
                       "Right-arrow virtual key code must be 124")
    }

    // MARK: - Action keys

    func test_returnKey_is36() {
        XCTAssertEqual(KeyCode.returnKey, 36,
                       "Return virtual key code must be 36")
    }

    func test_numpadEnter_is76() {
        XCTAssertEqual(KeyCode.numpadEnter, 76,
                       "Numpad-Enter virtual key code must be 76")
    }

    func test_escape_is53() {
        XCTAssertEqual(KeyCode.escape, 53,
                       "Escape virtual key code must be 53 — closing modals depends on this")
    }

    func test_tab_is48() {
        XCTAssertEqual(KeyCode.tab, 48,
                       "Tab virtual key code must be 48")
    }

    // MARK: - Type constraint

    func test_allValues_areUInt16() {
        // Confirm the type is UInt16 (matches NSEvent.keyCode) — this catches
        // any refactor that accidentally widens the type.
        let codes: [UInt16] = [
            KeyCode.tab,
            KeyCode.escape,
            KeyCode.returnKey,
            KeyCode.numpadEnter,
            KeyCode.downArrow,
            KeyCode.upArrow,
            KeyCode.leftArrow,
            KeyCode.rightArrow,
        ]
        XCTAssertEqual(codes.count, 8)
    }

    // MARK: - Uniqueness

    func test_allValues_areDistinct() {
        let codes: Set<UInt16> = [
            KeyCode.tab,
            KeyCode.escape,
            KeyCode.returnKey,
            KeyCode.numpadEnter,
            KeyCode.downArrow,
            KeyCode.upArrow,
            KeyCode.leftArrow,
            KeyCode.rightArrow,
        ]
        XCTAssertEqual(codes.count, 8, "Every KeyCode constant must map to a distinct key")
    }

    // MARK: - Arrow-key relationships

    func test_upAndDownArrow_areConsecutive() {
        // macOS assigns 125/126 to down/up; they differ by exactly 1.
        XCTAssertEqual(KeyCode.downArrow + 1, KeyCode.upArrow)
    }

    func test_leftAndRightArrow_areConsecutive() {
        // macOS assigns 123/124 to left/right; they differ by exactly 1.
        XCTAssertEqual(KeyCode.leftArrow + 1, KeyCode.rightArrow)
    }
}
