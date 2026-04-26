import XCTest
import AppKit
@testable import Synapse

/// Tests for auto-continuation and auto-increment of lists when pressing Enter in the editor.
///
/// These tests drive `insertNewline(_:)` on a real `LinkAwareTextView`, then inspect
/// the resulting string and cursor position.
final class ListContinuationTests: XCTestCase {

    var textView: LinkAwareTextView!

    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView()
        textView.isEditable = true
        textView.isSelectable = true
        // A frame is needed so the text view can accept text changes.
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    override func tearDown() {
        textView = nil
        super.tearDown()
    }

    /// Set the text view content and place the cursor at the end of the string.
    private func set(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    /// Trigger insertNewline as if the user pressed Return.
    private func pressReturn() {
        textView.insertNewline(nil)
    }

    // MARK: - Unordered bullet continuation

    func test_dashBullet_continuesOnEnter() {
        set("- first item")
        pressReturn()
        XCTAssertEqual(textView.string, "- first item\n- ")
    }

    func test_asteriskBullet_continuesOnEnter() {
        set("* first item")
        pressReturn()
        XCTAssertEqual(textView.string, "* first item\n* ")
    }

    func test_indentedBullet_preservesIndentAndContinues() {
        set("  - nested item")
        pressReturn()
        XCTAssertEqual(textView.string, "  - nested item\n  - ")
    }

    // MARK: - Ordered list auto-increment

    func test_orderedList_incrementsOneToTwo() {
        set("1. first item")
        pressReturn()
        XCTAssertEqual(textView.string, "1. first item\n2. ")
    }

    func test_orderedList_incrementsTwoToThree() {
        set("1. first\n2. second item")
        pressReturn()
        XCTAssertEqual(textView.string, "1. first\n2. second item\n3. ")
    }

    func test_orderedList_multiDigit_incrementsTenToEleven() {
        set("10. tenth item")
        pressReturn()
        XCTAssertEqual(textView.string, "10. tenth item\n11. ")
    }

    func test_orderedList_multiDigit_incrementsNinetyNineToOneHundred() {
        set("99. item")
        pressReturn()
        XCTAssertEqual(textView.string, "99. item\n100. ")
    }

    func test_orderedList_withIndent_preservesIndent() {
        set("  1. indented item")
        pressReturn()
        XCTAssertEqual(textView.string, "  1. indented item\n  2. ")
    }

    // MARK: - Task list continuation

    func test_checkedTaskItem_continuesAsUnchecked() {
        set("- [x] done task")
        pressReturn()
        XCTAssertEqual(textView.string, "- [x] done task\n- [ ] ")
    }

    func test_uncheckedTaskItem_continuesAsUnchecked() {
        set("- [ ] pending task")
        pressReturn()
        XCTAssertEqual(textView.string, "- [ ] pending task\n- [ ] ")
    }

    func test_asteriskTaskItem_continuesAsUnchecked() {
        set("* [x] done with asterisk")
        pressReturn()
        XCTAssertEqual(textView.string, "* [x] done with asterisk\n* [ ] ")
    }

    // MARK: - Empty bullet escape (double-enter breaks out of list)

    func test_emptyDashBullet_pressEnterRemovesBullet() {
        // "- " with no content — cursor is after the space
        set("- first item\n- ")
        pressReturn()
        // Should remove the empty bullet and insert a plain newline
        XCTAssertEqual(textView.string, "- first item\n\n")
    }

    func test_emptyAsteriskBullet_pressEnterRemovesBullet() {
        set("* first item\n* ")
        pressReturn()
        XCTAssertEqual(textView.string, "* first item\n\n")
    }

    func test_emptyOrderedItem_pressEnterRemovesNumber() {
        set("1. first item\n2. ")
        pressReturn()
        XCTAssertEqual(textView.string, "1. first item\n\n")
    }

    func test_emptyTaskItem_pressEnterRemovesMarker() {
        set("- [ ] first\n- [ ] ")
        pressReturn()
        XCTAssertEqual(textView.string, "- [ ] first\n\n")
    }

    // MARK: - Non-list lines

    func test_nonListLine_noIndent_noPrefix() {
        set("just some text")
        pressReturn()
        XCTAssertEqual(textView.string, "just some text\n")
    }

    func test_nonListLine_withIndent_preservesIndentOnly() {
        set("  indented text")
        pressReturn()
        XCTAssertEqual(textView.string, "  indented text\n  ")
    }
}
