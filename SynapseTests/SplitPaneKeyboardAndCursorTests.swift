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
        let textView = RawEditor.configuredTextView(isEditable: false)

        XCTAssertFalse(textView.isEditable)
    }

    func test_saveCursorObserver_ignoresReadOnlyTextViews() {
        let appState = AppState()
        let editableView = RawEditor.configuredTextView(isEditable: true)
        editableView.string = "Editable"
        editableView.setSelectedRange(NSRange(location: 4, length: 0))
        editableView.installSaveCursorObserver(appState: appState)

        let readOnlyView = RawEditor.configuredTextView(isEditable: false)
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

        let readOnlyView = RawEditor.configuredTextView(isEditable: false)

        let consumedRange = consumePendingCursorRange(from: appState, for: readOnlyView, paneIndex: 1)

        XCTAssertNil(consumedRange)
        XCTAssertEqual(appState.pendingCursorRange, NSRange(location: 3, length: 0))
    }

    func test_pendingCursorRange_isNotConsumedByWrongPane() {
        let appState = AppState()
        appState.pendingCursorRange = NSRange(location: 6, length: 0)
        appState.pendingCursorTargetPaneIndex = 0

        let editableView = RawEditor.configuredTextView(isEditable: true)

        let consumedRange = consumePendingCursorRange(from: appState, for: editableView, paneIndex: 1)

        XCTAssertNil(consumedRange)
        XCTAssertEqual(appState.pendingCursorRange, NSRange(location: 6, length: 0))
        XCTAssertEqual(appState.pendingCursorTargetPaneIndex, 0)
    }
}
