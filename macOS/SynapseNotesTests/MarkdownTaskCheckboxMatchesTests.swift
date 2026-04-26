import XCTest
@testable import Synapse

/// Tests for MarkdownTaskCheckboxInteraction.matches — enumerates all task items for editor/preview logic.
final class MarkdownTaskCheckboxMatchesTests: XCTestCase {

    func test_matches_emptySource_returnsEmpty() {
        XCTAssertEqual(MarkdownTaskCheckboxInteraction.matches(in: ""), [])
    }

    func test_matches_singleUncheckedTask_returnsOneHit() {
        let source = "- [ ] One"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].isChecked, false)
        XCTAssertEqual(hits[0].markerRange, NSRange(location: 2, length: 3))
        XCTAssertEqual(hits[0].replacement, "[x]")
    }

    func test_matches_singleCheckedTask_replacementUnchecks() {
        let source = "- [x] Done"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].isChecked, true)
        XCTAssertEqual(hits[0].replacement, "[ ]")
    }

    func test_matches_multipleTasks_preservesOrderAndRanges() {
        let source = "- [ ] First\n- [x] Second\n* [ ] Third"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits[0].isChecked, false)
        XCTAssertEqual(hits[1].isChecked, true)
        XCTAssertEqual(hits[2].isChecked, false)

        let ns = source as NSString
        for hit in hits {
            let marker = ns.substring(with: hit.markerRange)
            XCTAssertTrue(marker == "[ ]" || marker == "[x]", "marker text should be checkbox token, got: \(marker)")
        }
    }

    func test_hit_characterInsideMarker_returnsHit() {
        let source = "- [ ] Task"
        // Index 3 is inside "[ ]" (locations 2–4)
        let hit = MarkdownTaskCheckboxInteraction.hit(in: source, at: 3)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.isChecked, false)
    }

    func test_hit_characterOnBullet_returnsNil() {
        let source = "- [ ] Task"
        let hit = MarkdownTaskCheckboxInteraction.hit(in: source, at: 0)
        XCTAssertNil(hit)
    }

    func test_hit_nsNotFound_returnsNil() {
        XCTAssertNil(MarkdownTaskCheckboxInteraction.hit(in: "- [ ] x", at: NSNotFound))
    }
}
