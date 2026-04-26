import XCTest
@testable import Synapse

/// Tests for `SettingsManager.insertNotePane(fileURL:toSidebar:at:)` — the mechanism
/// that lets users pin arbitrary note files into sidebar pane slots (drag-and-drop from
/// the file tree onto a sidebar).  This was previously completely untested despite being
/// the only path for customising which notes appear in the sidebar.
final class SettingsManagerNotePaneTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!
    var noteFile: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        configFilePath = tempDir.appendingPathComponent("settings.json").path
        sut = SettingsManager(configPath: configFilePath)

        noteFile = tempDir.appendingPathComponent("my-note.md")
        try! "# Note".write(to: noteFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Append behaviour (no explicit index)

    func test_insertNotePane_appendsToSidebar_whenNoIndexGiven() {
        let leftID = FixedSidebar.leftID
        let initialCount = sut.sidebars.first { $0.id == leftID }!.panes.count

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        XCTAssertEqual(sidebar.panes.count, initialCount + 1,
                       "insertNotePane should append a pane when no index is given")
    }

    func test_insertNotePane_appendedPane_isNoteKind() {
        let leftID = FixedSidebar.leftID

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        let last = sidebar.panes.last
        XCTAssertNotNil(last?.notePane, "The inserted pane should be a note pane")
    }

    func test_insertNotePane_appendedPane_hasCorrectURL() {
        let leftID = FixedSidebar.leftID

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        let notePane = sidebar.panes.last?.notePane
        XCTAssertEqual(notePane?.fileURL.standardizedFileURL, noteFile.standardizedFileURL,
                       "Inserted note pane should reference the correct file URL")
    }

    // MARK: - Insertion at specific index

    func test_insertNotePane_atIndex0_insertsAtFront() {
        let leftID = FixedSidebar.leftID

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID, at: 0)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        XCTAssertNotNil(sidebar.panes.first?.notePane,
                        "Inserting at index 0 should place the note pane first")
    }

    func test_insertNotePane_atValidIndex_insertsAtCorrectPosition() {
        let leftID = FixedSidebar.leftID
        // Default left sidebar has [files, links]; inserting at index 1 puts note between them.

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID, at: 1)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        XCTAssertNotNil(sidebar.panes[1].notePane,
                        "Note pane should be at index 1")
    }

    func test_insertNotePane_atOutOfBoundsIndex_clampsToEnd() {
        let leftID = FixedSidebar.leftID
        let initialCount = sut.sidebars.first { $0.id == leftID }!.panes.count

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID, at: 999)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        XCTAssertEqual(sidebar.panes.count, initialCount + 1,
                       "Out-of-bounds index should clamp and still insert the pane")
        XCTAssertNotNil(sidebar.panes.last?.notePane,
                        "Clamped insertion should place the note pane at the end")
    }

    func test_insertNotePane_atNegativeIndex_clampsToFront() {
        let leftID = FixedSidebar.leftID

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID, at: -5)

        let sidebar = sut.sidebars.first { $0.id == leftID }!
        XCTAssertNotNil(sidebar.panes.first?.notePane,
                        "Negative index should clamp to 0 and insert at the front")
    }

    // MARK: - Guard: shouldShowFile

    func test_insertNotePane_hiddenFile_isNotInserted() {
        // Configure the filter so that ".hidden.md" is excluded.
        sut.hiddenFileFolderFilter = ".hidden*"

        let hiddenFile = tempDir.appendingPathComponent(".hidden.md")
        try! "secret".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let leftID = FixedSidebar.leftID
        let countBefore = sut.sidebars.first { $0.id == leftID }!.panes.count

        sut.insertNotePane(fileURL: hiddenFile, toSidebar: leftID)

        let countAfter = sut.sidebars.first { $0.id == leftID }!.panes.count
        XCTAssertEqual(countBefore, countAfter,
                       "A file excluded by the hidden-files filter should not be inserted")
    }

    // MARK: - Guard: unknown sidebar ID

    func test_insertNotePane_unknownSidebarID_doesNothing() {
        let bogusID = UUID()
        let sidebarCountsBefore = sut.sidebars.map { $0.panes.count }

        sut.insertNotePane(fileURL: noteFile, toSidebar: bogusID)

        let sidebarCountsAfter = sut.sidebars.map { $0.panes.count }
        XCTAssertEqual(sidebarCountsBefore, sidebarCountsAfter,
                       "An unrecognised sidebar ID should leave all sidebars unchanged")
    }

    // MARK: - Multiple inserts

    func test_insertNotePane_calledTwiceWithDifferentFiles_insertsBoth() {
        let noteFile2 = tempDir.appendingPathComponent("other-note.md")
        try! "# Other".write(to: noteFile2, atomically: true, encoding: .utf8)

        let leftID = FixedSidebar.leftID
        let countBefore = sut.sidebars.first { $0.id == leftID }!.panes.count

        sut.insertNotePane(fileURL: noteFile, toSidebar: leftID)
        sut.insertNotePane(fileURL: noteFile2, toSidebar: leftID)

        let countAfter = sut.sidebars.first { $0.id == leftID }!.panes.count
        XCTAssertEqual(countAfter, countBefore + 2,
                       "Two different files should each add one pane")
    }
}
