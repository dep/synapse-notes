import XCTest
@testable import Synapse

/// Regression: Replace with a stale cached match range must not crash.
///
/// `reapplySearchHighlights()` skips out-of-bounds ranges when repainting but
/// leaves `lastSearchHighlightRanges` unchanged. A Replace action must not call
/// `replaceCharacters` with those stale NSRanges.
final class FindReplaceStaleHighlightTests: XCTestCase {

    func test_replaceCurrentMatch_afterEditInvalidatesCachedRange_doesNotCrash() {
        let textView = LinkAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.isEditable = true
        textView.participatesInGlobalSearch = true
        textView.installSearchObservers()
        textView.string = "aaatest"

        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.query: "test", SearchMatchKey.matchIndex: 0]
        )

        guard let storage = textView.textStorage else {
            XCTFail("expected text storage")
            return
        }

        storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")
        XCTAssertEqual(textView.string, "test")
        textView.applyMarkdownStyling()

        NotificationCenter.default.post(
            name: .replaceCurrentMatch,
            object: nil,
            userInfo: [
                SearchMatchKey.query: "test",
                SearchMatchKey.matchIndex: 0,
                SearchMatchKey.replacement: "x",
                SearchMatchKey.advanceAfter: false,
            ]
        )

        XCTAssertEqual(textView.string, "test")
    }
}
