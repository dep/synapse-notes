import XCTest
import Combine
@testable import Synapse

/// Regression coverage for the observation split (#254): EditorState is the sole
/// owner of keystroke-frequency editor state, and mutating it must NOT fire
/// AppState.objectWillChange. AppState exposes non-published forwarding accessors
/// so existing call sites keep working against the same storage.
final class AppStateObservationSplitTests: XCTestCase {

    var sut: AppState!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AppState()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Mutating editor state must not invalidate AppState observers

    func test_mutatingEditorState_doesNotFireAppStateObjectWillChange() {
        var appStateChanges = 0
        sut.objectWillChange.sink { _ in appStateChanges += 1 }.store(in: &cancellables)

        sut.editorState.fileContent = "typed a character"
        sut.editorState.isDirty = true
        sut.editorState.pendingCursorPosition = 5
        sut.editorState.pendingCursorRange = NSRange(location: 0, length: 3)
        sut.editorState.pendingCursorTargetPaneIndex = 1
        sut.editorState.pendingScrollOffsetY = 42
        sut.editorState.pendingSearchQuery = "query"

        XCTAssertEqual(appStateChanges, 0,
                       "Keystroke-frequency EditorState mutations must not re-render AppState observers")
    }

    func test_mutatingForwardingAccessorsOnAppState_doesNotFireAppStateObjectWillChange() {
        var appStateChanges = 0
        sut.objectWillChange.sink { _ in appStateChanges += 1 }.store(in: &cancellables)

        sut.fileContent = "typed via forwarding accessor"
        sut.isDirty = true
        sut.pendingCursorPosition = 7
        sut.pendingCursorRange = NSRange(location: 1, length: 2)
        sut.pendingCursorTargetPaneIndex = 0
        sut.pendingScrollOffsetY = 99
        sut.pendingSearchQuery = "find me"

        XCTAssertEqual(appStateChanges, 0,
                       "AppState forwarding accessors are not @Published and must not fire objectWillChange")
    }

    // MARK: - EditorState observers still get notified

    func test_mutatingEditorState_firesEditorStateObjectWillChange() {
        var editorStateChanges = 0
        sut.editorState.objectWillChange.sink { _ in editorStateChanges += 1 }.store(in: &cancellables)

        sut.editorState.fileContent = "typed a character"
        sut.editorState.isDirty = true

        XCTAssertEqual(editorStateChanges, 2,
                       "Views observing EditorState must be invalidated by editor mutations")
    }

    func test_mutatingForwardingAccessorsOnAppState_firesEditorStateObjectWillChange() {
        var editorStateChanges = 0
        sut.editorState.objectWillChange.sink { _ in editorStateChanges += 1 }.store(in: &cancellables)

        sut.fileContent = "typed via forwarding accessor"
        sut.isDirty = true

        XCTAssertEqual(editorStateChanges, 2,
                       "Forwarding accessors write the same EditorState storage and must publish there")
    }

    // MARK: - Forwarding accessors share one source of truth

    func test_forwardingAccessors_readAndWriteEditorStateStorage() {
        sut.fileContent = "via appState"
        XCTAssertEqual(sut.editorState.fileContent, "via appState")

        sut.editorState.fileContent = "via editorState"
        XCTAssertEqual(sut.fileContent, "via editorState")

        sut.isDirty = true
        XCTAssertTrue(sut.editorState.isDirty)

        sut.pendingCursorRange = NSRange(location: 3, length: 4)
        XCTAssertEqual(sut.editorState.pendingCursorRange, NSRange(location: 3, length: 4))

        sut.editorState.pendingSearchQuery = "shared"
        XCTAssertEqual(sut.pendingSearchQuery, "shared")
    }

    // MARK: - Pending-signal consumption lives on EditorState

    func test_consumeHelpers_onEditorState_clearSharedStorage() {
        let textView = NSTextView()
        textView.isEditable = true

        sut.pendingCursorRange = NSRange(location: 0, length: 2)
        sut.pendingCursorTargetPaneIndex = nil
        XCTAssertEqual(sut.editorState.consumePendingCursorRange(for: textView, paneIndex: 0),
                       NSRange(location: 0, length: 2))
        XCTAssertNil(sut.pendingCursorRange, "Consumption must clear the single shared storage")

        sut.pendingSearchQuery = "needle"
        XCTAssertEqual(sut.editorState.consumePendingSearchQuery(), "needle")
        XCTAssertNil(sut.pendingSearchQuery)
    }
}
