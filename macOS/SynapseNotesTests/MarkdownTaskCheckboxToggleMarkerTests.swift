import XCTest
@testable import Synapse

/// Tests for toggling a task checkbox marker by UTF-16 offset — the path driven by
/// the markdown preview's `data-offset` attributes (Issue #255: this used to be a
/// force-unwrapped `Range(NSRange, in:)` conversion in EditorView).
final class MarkdownTaskCheckboxToggleMarkerTests: XCTestCase {

    // MARK: - Characterization: marker offsets are UTF-16 and emoji-safe

    /// The parser/renderer compute marker offsets in UTF-16 units, so even with
    /// emoji and other multibyte characters before the checkbox the NSRange both
    /// addresses the literal marker and converts cleanly to a String range.
    func test_markerRange_withEmojiBeforeCheckbox_isUTF16AndConvertible() {
        let source = "🚀🚀 rocket line\n- [ ] task with emoji 🎉\n- [x] done ✅"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 2)

        let ns = source as NSString
        XCTAssertEqual(ns.substring(with: hits[0].markerRange), "[ ]")
        XCTAssertEqual(ns.substring(with: hits[1].markerRange), "[x]")
        for hit in hits {
            XCTAssertNotNil(Range(hit.markerRange, in: source),
                            "A 3-unit ASCII marker must always convert to a String range")
        }
    }

    // MARK: - togglingMarker(in:atUTF16Offset:)

    func test_togglingMarker_unchecked_withEmojiBeforeCheckbox_checks() {
        let source = "🚀🚀 rocket line\n- [ ] task with emoji 🎉"
        let offset = MarkdownTaskCheckboxInteraction.matches(in: source)[0].markerRange.location

        let toggled = MarkdownTaskCheckboxInteraction.togglingMarker(in: source, atUTF16Offset: offset)

        XCTAssertEqual(toggled, "🚀🚀 rocket line\n- [x] task with emoji 🎉")
    }

    func test_togglingMarker_checked_withEmojiBeforeCheckbox_unchecks() {
        let source = "🚀 rocket\n- [x] done ✅"
        let offset = MarkdownTaskCheckboxInteraction.matches(in: source)[0].markerRange.location

        let toggled = MarkdownTaskCheckboxInteraction.togglingMarker(in: source, atUTF16Offset: offset)

        XCTAssertEqual(toggled, "🚀 rocket\n- [ ] done ✅")
    }

    func test_togglingMarker_uppercaseChecked_unchecks() {
        let toggled = MarkdownTaskCheckboxInteraction.togglingMarker(in: "- [X] done", atUTF16Offset: 2)

        XCTAssertEqual(toggled, "- [ ] done")
    }

    func test_togglingMarker_plainASCII_checks() {
        let toggled = MarkdownTaskCheckboxInteraction.togglingMarker(in: "- [ ] task", atUTF16Offset: 2)

        XCTAssertEqual(toggled, "- [x] task")
    }

    func test_togglingMarker_offsetBeyondEnd_returnsNil() {
        XCTAssertNil(MarkdownTaskCheckboxInteraction.togglingMarker(in: "- [ ]", atUTF16Offset: 3))
        XCTAssertNil(MarkdownTaskCheckboxInteraction.togglingMarker(in: "", atUTF16Offset: 0))
    }

    func test_togglingMarker_negativeOffset_returnsNil() {
        XCTAssertNil(MarkdownTaskCheckboxInteraction.togglingMarker(in: "- [ ] task", atUTF16Offset: -1))
    }

    func test_togglingMarker_staleOffsetSplittingEmoji_returnsNilWithoutCrash() {
        // Offset 1 lands inside the rocket emoji's surrogate pair — the crash case
        // the old force unwrap was vulnerable to with stale preview offsets.
        XCTAssertNil(MarkdownTaskCheckboxInteraction.togglingMarker(in: "🚀 - [ ] task", atUTF16Offset: 1))
    }

    func test_togglingMarker_staleOffsetOnNonMarkerText_returnsNil() {
        // The old inline code replaced ANY 3 characters with "[ ]" — silent text
        // corruption on stale offsets. Non-marker text must now be left untouched.
        XCTAssertNil(MarkdownTaskCheckboxInteraction.togglingMarker(in: "hello world", atUTF16Offset: 0))
    }
}
