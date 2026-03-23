import XCTest
import AppKit
@testable import Synapse

@MainActor
final class SplitPaneKeyboardAndCursorTests: XCTestCase {
    func test_paneSwitchShortcut_matchesArrowKeysWithNumericPadModifier() {
        XCTAssertTrue(
            shouldConsumePaneSwitchShortcut(
                keyCode: 124,
                modifierFlags: [.command, .option, .numericPad],
                splitOrientation: .vertical
            )
        )

        XCTAssertTrue(
            shouldConsumePaneSwitchShortcut(
                keyCode: 126,
                modifierFlags: [.command, .option, .numericPad],
                splitOrientation: .horizontal
            )
        )
    }

    func test_paneSwitchShortcut_rejectsUnexpectedModifiers() {
        XCTAssertFalse(
            shouldConsumePaneSwitchShortcut(
                keyCode: 124,
                modifierFlags: [.command, .option, .shift, .numericPad],
                splitOrientation: .vertical
            )
        )
    }

    func test_configuredTextView_readOnlyModeDisablesEditing() {
        let textView = RawEditor.configuredTextView(isEditable: false, settings: nil)

        XCTAssertFalse(textView.isEditable)
    }

    func test_saveCursorObserver_ignoresReadOnlyTextViews() {
        let appState = AppState()
        let editableView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        editableView.string = "Editable"
        editableView.setSelectedRange(NSRange(location: 4, length: 0))
        editableView.installSaveCursorObserver(appState: appState)

        let readOnlyView = RawEditor.configuredTextView(isEditable: false, settings: nil)
        readOnlyView.string = "Read only"
        readOnlyView.setSelectedRange(NSRange(location: 0, length: 0))
        readOnlyView.installSaveCursorObserver(appState: appState)

        NotificationCenter.default.post(name: .saveCursorPosition, object: nil)

        XCTAssertEqual(appState.pendingCursorRange, NSRange(location: 4, length: 0))
    }

    func test_pendingCursorRange_isNotConsumedByReadOnlyTextView() {
        let appState = AppState()
        appState.pendingCursorRange = NSRange(location: 3, length: 0)
        appState.pendingCursorTargetPaneIndex = 0

        let readOnlyView = RawEditor.configuredTextView(isEditable: false, settings: nil)

        let consumedRange = consumePendingCursorRange(from: appState, for: readOnlyView, paneIndex: 1)

        XCTAssertNil(consumedRange)
        XCTAssertEqual(appState.pendingCursorRange, NSRange(location: 3, length: 0))
    }

    func test_pendingCursorRange_isNotConsumedByWrongPane() {
        let appState = AppState()
        appState.pendingCursorRange = NSRange(location: 6, length: 0)
        appState.pendingCursorTargetPaneIndex = 0

        let editableView = RawEditor.configuredTextView(isEditable: true, settings: nil)

        let consumedRange = consumePendingCursorRange(from: appState, for: editableView, paneIndex: 1)

        XCTAssertNil(consumedRange)
        XCTAssertEqual(appState.pendingCursorRange, NSRange(location: 6, length: 0))
        XCTAssertEqual(appState.pendingCursorTargetPaneIndex, 0)
    }

    func test_saveCursorObserver_tracksEditableScrollOffset() {
        let appState = AppState()
        let editableView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        let scrollView = NSScrollView()
        scrollView.documentView = editableView
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 42))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        editableView.installSaveCursorObserver(appState: appState)

        NotificationCenter.default.post(name: .saveCursorPosition, object: nil)

        XCTAssertEqual(appState.pendingScrollOffsetY, 42)
    }

    func test_preserveScrollOffset_restoresPreviousOffsetAfterAction() {
        let textView = RawEditor.configuredTextView(isEditable: true, settings: nil)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 42))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        preserveScrollOffset(for: textView) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 42)
    }

    func test_activatePaneOnReadOnlyInteraction_triggersPaneActivation() {
        var activated = false

        let consumed = activatePaneOnReadOnlyInteraction(isEditable: false) {
            activated = true
        }

        XCTAssertTrue(consumed)
        XCTAssertTrue(activated)
    }
}
