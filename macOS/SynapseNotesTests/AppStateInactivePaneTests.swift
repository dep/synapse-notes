import XCTest
@testable import Synapse

/// Tests for AppState.inactivePane(_:):
/// - The active pane returns live (current) tabs and activeTabIndex.
/// - An inactive pane returns its stored snapshot.
/// - An out-of-bounds index returns an empty PaneState.
final class AppStateInactivePaneTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!
    var fileB: URL!
    var fileC: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        fileA = tempDir.appendingPathComponent("NoteA.md")
        fileB = tempDir.appendingPathComponent("NoteB.md")
        fileC = tempDir.appendingPathComponent("NoteC.md")

        try! "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        try! "Content B".write(to: fileB, atomically: true, encoding: .utf8)
        try! "Content C".write(to: fileC, atomically: true, encoding: .utf8)

        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Active pane returns live state

    func test_inactivePane_forActivePaneIndex_returnsLiveTabs() {
        sut.openFile(fileA)
        sut.splitVertically() // activePaneIndex = 1
        sut.openFileInNewTab(fileB) // pane 1 now has 2 tabs

        let livePane = sut.inactivePane(sut.activePaneIndex)
        XCTAssertEqual(livePane.tabs, sut.tabs,
                       "inactivePane for the active pane should return live tab state")
    }

    func test_inactivePane_forActivePaneIndex_returnsLiveActiveTabIndex() {
        sut.openFile(fileA)
        sut.splitVertically()

        let livePane = sut.inactivePane(sut.activePaneIndex)
        XCTAssertEqual(livePane.activeTabIndex, sut.activeTabIndex,
                       "inactivePane for the active pane should return live activeTabIndex")
    }

    // MARK: - Inactive pane returns snapshot state

    func test_inactivePane_forInactivePaneIndex_returnsSnapshot() {
        sut.openFile(fileA) // pane 0 has fileA
        sut.splitVertically() // creates split; pane 1 becomes active

        // Now on pane 1; open fileB
        sut.openFile(fileB)

        // inactivePane(0) should return pane 0's snapshot with fileA
        let pane0Snapshot = sut.inactivePane(0)
        XCTAssertEqual(pane0Snapshot.selectedFile, fileA,
                       "Snapshot of pane 0 should contain the file that was open before splitting")
    }

    func test_inactivePane_forInactivePaneIndex_doesNotReflectLiveChanges() {
        sut.openFile(fileA) // pane 0 has fileA
        sut.splitVertically() // pane 1 active
        sut.openFile(fileB) // pane 1 now shows fileB

        // Switch back to pane 0 and open fileC
        sut.activePaneIndex = 0
        sut.openFile(fileC) // pane 0 now shows fileC

        // Snapshot of pane 1 should still hold fileB
        let pane1Snapshot = sut.inactivePane(1)
        XCTAssertEqual(pane1Snapshot.selectedFile, fileB,
                       "Inactive pane snapshot should not reflect changes made while pane was inactive")
    }

    // MARK: - Out-of-bounds returns empty PaneState

    func test_inactivePane_outOfBoundsIndex_returnsEmptyState() {
        sut.openFile(fileA)
        let empty = sut.inactivePane(99)
        XCTAssertTrue(empty.tabs.isEmpty, "Out-of-bounds index should return PaneState with no tabs")
        XCTAssertNil(empty.activeTabIndex, "Out-of-bounds index should return PaneState with nil activeTabIndex")
        XCTAssertNil(empty.selectedFile, "Out-of-bounds index should return PaneState with nil selectedFile")
    }

    // MARK: - Single pane (no split)

    func test_inactivePane_withNoSplit_pane0IsLive() {
        sut.openFile(fileA)
        XCTAssertEqual(sut.activePaneIndex, 0)

        let pane0 = sut.inactivePane(0)
        XCTAssertEqual(pane0.tabs, sut.tabs, "Without split, pane 0 should return live state")
    }
}
