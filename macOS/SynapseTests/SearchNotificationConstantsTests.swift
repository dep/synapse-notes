import XCTest
@testable import Synapse

/// Tests for Notification.Name identifiers and SearchMatchKey constants.
///
/// These string constants are the communication channel between the find-bar
/// UI and the editor text view.  If any identifier silently drifts the search
/// feature stops working without a compile-time error.
final class SearchNotificationConstantsTests: XCTestCase {

    // MARK: - Notification.Name identifiers

    func test_scrollToSearchMatch_identifier() {
        XCTAssertEqual(
            Notification.Name.scrollToSearchMatch.rawValue,
            "Synapse.scrollToSearchMatch",
            "Changing this breaks editor scroll-to-match"
        )
    }

    func test_clearSearchHighlights_identifier() {
        XCTAssertEqual(
            Notification.Name.clearSearchHighlights.rawValue,
            "Synapse.clearSearchHighlights"
        )
    }

    func test_advanceSearchMatch_identifier() {
        XCTAssertEqual(
            Notification.Name.advanceSearchMatch.rawValue,
            "Synapse.advanceSearchMatch",
            "Changing this breaks CMD-G / Shift-CMD-G shortcut"
        )
    }

    func test_focusEditor_identifier() {
        XCTAssertEqual(
            Notification.Name.focusEditor.rawValue,
            "Synapse.focusEditor"
        )
    }

    func test_saveCursorPosition_identifier() {
        XCTAssertEqual(
            Notification.Name.saveCursorPosition.rawValue,
            "Synapse.saveCursorPosition"
        )
    }

    func test_commandKPressed_identifier() {
        XCTAssertEqual(
            Notification.Name.commandKPressed.rawValue,
            "Synapse.commandKPressed",
            "Changing this breaks the CMD-K wiki-link shortcut"
        )
    }

    // MARK: - Notification names are distinct

    func test_allNotificationNames_areDistinct() {
        let names: Set<String> = [
            Notification.Name.scrollToSearchMatch.rawValue,
            Notification.Name.clearSearchHighlights.rawValue,
            Notification.Name.advanceSearchMatch.rawValue,
            Notification.Name.focusEditor.rawValue,
            Notification.Name.saveCursorPosition.rawValue,
            Notification.Name.commandKPressed.rawValue,
        ]
        XCTAssertEqual(names.count, 6, "Every notification name must be unique")
    }

    // MARK: - Notification names share the "Synapse." namespace

    func test_allNotificationNames_haveCorrectNamespace() {
        let names = [
            Notification.Name.scrollToSearchMatch,
            Notification.Name.clearSearchHighlights,
            Notification.Name.advanceSearchMatch,
            Notification.Name.focusEditor,
            Notification.Name.saveCursorPosition,
            Notification.Name.commandKPressed,
        ]
        for name in names {
            XCTAssertTrue(
                name.rawValue.hasPrefix("Synapse."),
                "Notification '\(name.rawValue)' should start with 'Synapse.'"
            )
        }
    }

    // MARK: - SearchMatchKey constants

    func test_searchMatchKey_query() {
        XCTAssertEqual(SearchMatchKey.query, "query",
                       "Used as userInfo key when posting scrollToSearchMatch")
    }

    func test_searchMatchKey_matchIndex() {
        XCTAssertEqual(SearchMatchKey.matchIndex, "matchIndex")
    }

    func test_searchMatchKey_delta() {
        XCTAssertEqual(SearchMatchKey.delta, "delta",
                       "Used as userInfo key when advancing the search match")
    }

    func test_searchMatchKeys_areDistinct() {
        let keys: Set<String> = [
            SearchMatchKey.query,
            SearchMatchKey.matchIndex,
            SearchMatchKey.delta,
        ]
        XCTAssertEqual(keys.count, 3, "SearchMatchKey constants must be unique strings")
    }

    // MARK: - Notification round-trip

    func test_scrollToSearchMatch_canBePostedAndReceived() {
        let expectation = self.expectation(description: "Notification received")
        let query = "hello"
        let matchIdx = 3

        let observer = NotificationCenter.default.addObserver(
            forName: .scrollToSearchMatch,
            object: nil,
            queue: .main
        ) { note in
            let receivedQuery = note.userInfo?[SearchMatchKey.query] as? String
            let receivedIndex = note.userInfo?[SearchMatchKey.matchIndex] as? Int
            XCTAssertEqual(receivedQuery, query)
            XCTAssertEqual(receivedIndex, matchIdx)
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.query: query, SearchMatchKey.matchIndex: matchIdx]
        )

        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func test_advanceSearchMatch_canBePostedAndReceived() {
        let expectation = self.expectation(description: "Advance notification received")
        let delta = -1

        let observer = NotificationCenter.default.addObserver(
            forName: .advanceSearchMatch,
            object: nil,
            queue: .main
        ) { note in
            let receivedDelta = note.userInfo?[SearchMatchKey.delta] as? Int
            XCTAssertEqual(receivedDelta, delta)
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .advanceSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.delta: delta]
        )

        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
