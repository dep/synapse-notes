import XCTest
@testable import Synapse

/// Guards for inline find/replace: cached highlight ranges must not drive replace after the buffer changed.
final class SearchReplaceStaleHighlightTests: XCTestCase {

    func test_cachedHighlightRangeStillMatchesQuery_validMatch() {
        XCTAssertTrue(
            LinkAwareTextView.cachedHighlightRangeStillMatchesQuery(
                range: NSRange(location: 4, length: 3),
                fullString: "foo bar baz",
                query: "BAR"
            )
        )
    }

    func test_cachedHighlightRangeStillMatchesQuery_outOfBounds_returnsFalse() {
        XCTAssertFalse(
            LinkAwareTextView.cachedHighlightRangeStillMatchesQuery(
                range: NSRange(location: 8, length: 10),
                fullString: "short",
                query: "x"
            )
        )
    }

    func test_cachedHighlightRangeStillMatchesQuery_wrongSpan_returnsFalse() {
        XCTAssertFalse(
            LinkAwareTextView.cachedHighlightRangeStillMatchesQuery(
                range: NSRange(location: 0, length: 3),
                fullString: "foo bar",
                query: "bar"
            )
        )
    }
}
