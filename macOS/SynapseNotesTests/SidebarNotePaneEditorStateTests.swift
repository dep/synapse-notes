import XCTest
@testable import Synapse

/// `SidebarNotePaneEditorState` debounces writes and must flush on disappear to avoid losing edits.
final class SidebarNotePaneEditorStateTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_initialContent_loadsFromDisk() {
        let file = tempDir.appendingPathComponent("pane.md")
        let original = "hello"
        try! original.write(to: file, atomically: true, encoding: .utf8)

        let pane = SidebarNotePane(fileURL: file)
        let state = SidebarNotePaneEditorState(notePane: pane)

        XCTAssertEqual(state.fileContent, "hello")
        XCTAssertFalse(state.isDirty)
    }

    func test_flush_writesImmediatelyWhenDirty() {
        let file = tempDir.appendingPathComponent("flush.md")
        try! "a".write(to: file, atomically: true, encoding: .utf8)

        let state = SidebarNotePaneEditorState(notePane: SidebarNotePane(fileURL: file))
        state.fileContent = "b"
        state.isDirty = true

        state.flush()

        XCTAssertFalse(state.isDirty)
        let disk = try! String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(disk, "b")
    }

    func test_flush_noOpWhenNotDirty() {
        let file = tempDir.appendingPathComponent("clean.md")
        try! "unchanged".write(to: file, atomically: true, encoding: .utf8)

        let state = SidebarNotePaneEditorState(notePane: SidebarNotePane(fileURL: file))
        state.flush()

        let disk = try! String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(disk, "unchanged")
    }
}
