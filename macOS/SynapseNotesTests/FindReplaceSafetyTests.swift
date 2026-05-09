import XCTest
import AppKit
@testable import Synapse

/// Regression tests for find/replace when cached highlight ranges lag behind the document.
final class FindReplaceSafetyTests: XCTestCase {

    func test_replaceCurrent_skipsWhenCachedRangeNoLongerContainsQuery() {
        let textView = LinkAwareTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.isEditable = true
        textView.participatesInGlobalSearch = true
        textView.setPlainText("hello test world")

        textView.installSearchObservers()

        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.query: "test", SearchMatchKey.matchIndex: 0]
        )

        XCTAssertEqual(textView.string, "hello test world")

        // Edit without refreshing search highlights: "test" moves to the front, but the
        // cached match range still points at the old UTF-16 offset (now wrong text).
        guard let storage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }
        storage.replaceCharacters(in: NSRange(location: 0, length: 6), with: "")
        XCTAssertEqual(textView.string, "test world")

        NotificationCenter.default.post(
            name: .replaceCurrentMatch,
            object: nil,
            userInfo: [
                SearchMatchKey.query: "test",
                SearchMatchKey.matchIndex: 0,
                SearchMatchKey.replacement: "X",
                SearchMatchKey.advanceAfter: false,
            ]
        )

        XCTAssertEqual(
            textView.string,
            "test world",
            "Replace must not run when the cached range no longer matches the search string"
        )
    }
}
