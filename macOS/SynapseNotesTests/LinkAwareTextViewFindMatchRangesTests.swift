import XCTest
@testable import Synapse

/// `LinkAwareTextView.caseInsensitiveNonOverlappingMatchRanges` must stay aligned with find
/// highlights and replace-all so ranges never disagree for the same query and body text.
final class LinkAwareTextViewFindMatchRangesTests: XCTestCase {

    func test_emptyQuery_returnsNoRanges() {
        let ranges = LinkAwareTextView.caseInsensitiveNonOverlappingMatchRanges(
            in: "hello world",
            query: "",
            maxCount: nil
        )
        XCTAssertTrue(ranges.isEmpty)
    }

    func test_caseInsensitive_findsAllNonOverlapping() {
        let ranges = LinkAwareTextView.caseInsensitiveNonOverlappingMatchRanges(
            in: "Aa aa AA",
            query: "aA",
            maxCount: nil
        )
        XCTAssertEqual(ranges.count, 3)
    }

    func test_maxCount_stopsAfterFirst() {
        let ranges = LinkAwareTextView.caseInsensitiveNonOverlappingMatchRanges(
            in: "foo Foo FOO",
            query: "foo",
            maxCount: 1
        )
        XCTAssertEqual(ranges.count, 1)
    }
}
