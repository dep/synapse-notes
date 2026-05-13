import XCTest
import AppKit
@testable import Synapse

/// Covers `consumePendingSearchQuery` and related editor hand-off helpers in `EditorView.swift`.
@MainActor
final class EditorViewPendingStateConsumptionTests: XCTestCase {

    func test_consumePendingSearchQuery_nilWhenUnset() {
        let appState = AppState()
        XCTAssertNil(consumePendingSearchQuery(from: appState))
        XCTAssertNil(appState.pendingSearchQuery)
    }

    func test_consumePendingSearchQuery_returnsValueAndClears() {
        let appState = AppState()
        appState.pendingSearchQuery = "wikilink"
        XCTAssertEqual(consumePendingSearchQuery(from: appState), "wikilink")
        XCTAssertNil(appState.pendingSearchQuery)
    }

    func test_consumePendingCursorPosition_consumesWhenEditableAndPaneMatches() {
        let appState = AppState()
        appState.pendingCursorPosition = 12
        appState.pendingCursorTargetPaneIndex = 1

        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        let position = consumePendingCursorPosition(from: appState, for: textView, paneIndex: 1)

        XCTAssertEqual(position, 12)
        XCTAssertNil(appState.pendingCursorPosition)
        XCTAssertNil(appState.pendingCursorTargetPaneIndex)
    }

    func test_consumePendingCursorPosition_ignoredForReadOnlyTextView() {
        let appState = AppState()
        appState.pendingCursorPosition = 5
        appState.pendingCursorTargetPaneIndex = 0

        let textView = RawEditor.configuredTextView(isEditable: false, settings: nil)
        XCTAssertNil(consumePendingCursorPosition(from: appState, for: textView, paneIndex: 0))

        XCTAssertEqual(appState.pendingCursorPosition, 5)
        XCTAssertEqual(appState.pendingCursorTargetPaneIndex, 0)
    }

    func test_consumePendingCursorPosition_ignoredForWrongPaneWhenTargeted() {
        let appState = AppState()
        appState.pendingCursorPosition = 7
        appState.pendingCursorTargetPaneIndex = 0

        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        XCTAssertNil(consumePendingCursorPosition(from: appState, for: textView, paneIndex: 1))

        XCTAssertEqual(appState.pendingCursorPosition, 7)
        XCTAssertEqual(appState.pendingCursorTargetPaneIndex, 0)
    }

    func test_consumePendingCursorPosition_anyPaneWhenTargetNotSet() {
        let appState = AppState()
        appState.pendingCursorPosition = 3
        appState.pendingCursorTargetPaneIndex = nil

        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        XCTAssertEqual(consumePendingCursorPosition(from: appState, for: textView, paneIndex: 2), 3)
        XCTAssertNil(appState.pendingCursorPosition)
    }

    func test_consumePendingScrollOffset_returnsOffsetAndClearsScrollState() {
        let appState = AppState()
        appState.pendingScrollOffsetY = 88
        appState.pendingCursorTargetPaneIndex = nil

        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        let offset = consumePendingScrollOffset(from: appState, for: textView, paneIndex: 0)

        XCTAssertEqual(offset, 88)
        XCTAssertNil(appState.pendingScrollOffsetY)
    }

    func test_restoreScrollOffset_clampsToDocumentBounds() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 800))
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.contentView.setBoundsSize(NSSize(width: 200, height: 200))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        restoreScrollOffset(10_000, in: scrollView)

        let maxOffset = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, maxOffset, accuracy: 0.5)
    }

    /// Editing the note while the find bar stays open does not repost `scrollToSearchMatch`.
    /// Debounced markdown restyle re-applies highlights but skips out-of-bounds cached ranges
    /// without removing them, so Replace must not call `replaceCharacters` with a stale NSRange.
    func test_replaceCurrentMatch_doesNotCrashWhenCachedHighlightRangeIsStaleAfterBodyEdit() {
        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        textView.participatesInGlobalSearch = true
        textView.installSearchObservers()

        textView.setPlainText("aaaaaaaaaahello")
        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.query: "hello", SearchMatchKey.matchIndex: 0]
        )

        guard let storage = textView.textStorage else {
            XCTFail("expected text storage")
            return
        }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "no")
        storage.endEditing()
        textView.didChangeText()

        NotificationCenter.default.post(
            name: .replaceCurrentMatch,
            object: nil,
            userInfo: [
                SearchMatchKey.query: "hello",
                SearchMatchKey.matchIndex: 0,
                SearchMatchKey.replacement: "x",
                SearchMatchKey.advanceAfter: false,
            ]
        )

        XCTAssertEqual(textView.string, "no")
    }
}
