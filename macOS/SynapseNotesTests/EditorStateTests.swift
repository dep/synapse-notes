import XCTest
@testable import Synapse

/// Tests that EditorState exists as an ObservableObject and holds per-editor data.
final class EditorStateTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - EditorState is accessible from AppState

    func test_appState_exposes_editorState() {
        XCTAssertNotNil(sut.editorState)
    }

    func test_editorState_isObservableObject() {
        _ = sut.editorState.objectWillChange
        XCTAssertTrue(true, "EditorState conforms to ObservableObject")
    }

    // MARK: - EditorState owns editor-level published properties

    func test_editorState_selectedFile_initiallyNil() {
        XCTAssertNil(sut.editorState.selectedFile)
    }

    func test_editorState_fileContent_initiallyEmpty() {
        // EditorState.fileContent is initialised to empty; it is NOT synced from
        // AppState to avoid interleaving with NSUndoManager during Cmd+Z (see
        // bindSubObjectObservers comment). Views that need fileContent should
        // subscribe to appState directly.
        XCTAssertEqual(sut.editorState.fileContent, "")
    }

    func test_editorState_isDirty_initiallyFalse() {
        XCTAssertFalse(sut.editorState.isDirty)
    }

    // MARK: - AppState.selectedFile is mirrored into EditorState

    func test_appState_selectedFile_forwardsToEditorState() {
        let file = tempDir.appendingPathComponent("note.md")
        try! "hello".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)
        sut.openFile(file)
        XCTAssertEqual(sut.selectedFile, sut.editorState.selectedFile,
                       "appState.selectedFile must be mirrored into editorState.selectedFile")
    }

    // MARK: - High-frequency editor properties are NOT mirrored (crash safety)
    // fileContent, isDirty, pendingCursor*, pendingScrollOffsetY, and pendingSearchQuery
    // are intentionally NOT synced from AppState into EditorState. Sinking these during
    // @Published willSet can interleave with NSUndoManager and cause EXC_BAD_ACCESS on Cmd+Z.
    // Views that need them must subscribe to appState directly.
}
