import XCTest
@testable import Synapse

/// Tests for split pane functionality: two independent editor panes
final class AppStateSplitPaneTests: XCTestCase {
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

    // MARK: - Initial State

    func test_initialState_noSplit() {
        XCTAssertNil(sut.splitOrientation, "Should start with no split")
        XCTAssertEqual(sut.activePaneIndex, 0, "Active pane should be pane 0")
    }

    // MARK: - Opening Splits

    func test_splitVertically_createsTwoPanes() {
        sut.openFile(fileA)
        sut.splitVertically()

        XCTAssertEqual(sut.splitOrientation, .vertical, "Should have vertical split")
    }

    func test_splitHorizontally_createsTwoPanes() {
        sut.openFile(fileA)
        sut.splitHorizontally()

        XCTAssertEqual(sut.splitOrientation, .horizontal, "Should have horizontal split")
    }

    func test_splitVertically_activePaneSwitchesToPane1() {
        sut.openFile(fileA)
        sut.splitVertically()

        XCTAssertEqual(sut.activePaneIndex, 1, "Active pane should switch to new pane 1")
    }

    func test_splitVertically_newPaneShowsSameFile() {
        sut.openFile(fileA)
        sut.splitVertically()

        XCTAssertEqual(sut.selectedFile, fileA, "New pane should show the same file as the original pane")
    }

    // MARK: - Independent Pane State

    func test_openFileInPane1_doesNotAffectPane0() {
        sut.openFile(fileA)
        sut.splitVertically() // now in pane 1

        sut.openFile(fileB) // open in active pane (1)

        sut.activePaneIndex = 0
        XCTAssertEqual(sut.selectedFile, fileA, "Pane 0 should still show fileA")
    }

    func test_openFileInPane0_doesNotAffectPane1() {
        sut.openFile(fileA)
        sut.splitVertically() // pane 1 active, shows fileA

        sut.activePaneIndex = 0
        sut.openFile(fileB) // open in pane 0

        sut.activePaneIndex = 1
        XCTAssertEqual(sut.selectedFile, fileA, "Pane 1 should still show fileA")
    }

    func test_tabsAreIndependentPerPane() {
        sut.openFile(fileA)
        sut.splitVertically() // pane 1 active, tabs = [fileA]

        sut.openFileInNewTab(fileB) // add tab in pane 1

        sut.activePaneIndex = 0
        XCTAssertEqual(sut.tabs.count, 1, "Pane 0 should have 1 tab")
        XCTAssertEqual(sut.tabs[0], .file(fileA))

        sut.activePaneIndex = 1
        XCTAssertEqual(sut.tabs.count, 2, "Pane 1 should have 2 tabs")
    }

    // MARK: - Focus / Active Pane

    func test_focusPane_changesActivePaneIndex() {
        sut.openFile(fileA)
        sut.splitVertically()
        XCTAssertEqual(sut.activePaneIndex, 1)

        sut.focusPane(0)
        XCTAssertEqual(sut.activePaneIndex, 0)
    }

    func test_focusPane_invalidIndex_doesNothing() {
        sut.openFile(fileA)
        sut.splitVertically()

        sut.focusPane(5)
        XCTAssertEqual(sut.activePaneIndex, 1, "Should remain on pane 1")
    }

    // MARK: - Switching Focus Between Panes

    func test_switchToOtherPane_togglesBetweenPanes() {
        sut.openFile(fileA)
        sut.splitVertically() // active = 1

        sut.switchToOtherPane()
        XCTAssertEqual(sut.activePaneIndex, 0)

        sut.switchToOtherPane()
        XCTAssertEqual(sut.activePaneIndex, 1)
    }

    func test_switchToOtherPane_withNoSplit_doesNothing() {
        sut.openFile(fileA)
        XCTAssertNil(sut.splitOrientation)

        sut.switchToOtherPane()
        XCTAssertEqual(sut.activePaneIndex, 0, "Should remain on pane 0 with no split")
    }

    // MARK: - Closing a Pane

    func test_closePane_removesPane1_andFocusesPane0() {
        sut.openFile(fileA)
        sut.splitVertically()
        sut.openFile(fileB) // pane 1 shows fileB

        sut.closePane(1)

        XCTAssertNil(sut.splitOrientation, "Split should be gone after closing a pane")
        XCTAssertEqual(sut.activePaneIndex, 0, "Active pane should be pane 0")
        XCTAssertEqual(sut.selectedFile, fileA, "Should show pane 0's file")
    }

    func test_closePane0_makesPane1BecomePane0() {
        sut.openFile(fileA) // pane 0 has fileA
        sut.splitVertically()
        sut.openFile(fileB) // pane 1 has fileB

        sut.closePane(0)

        XCTAssertNil(sut.splitOrientation)
        XCTAssertEqual(sut.activePaneIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileB, "Former pane 1's file should now be in pane 0")
    }

    func test_closePane_withNoSplit_doesNothing() {
        sut.openFile(fileA)

        sut.closePane(0)

        XCTAssertNil(sut.splitOrientation, "Still no split")
        XCTAssertEqual(sut.selectedFile, fileA, "File should be unchanged")
    }

    // MARK: - Open In Split (from file tree context menu)

    func test_openInSplit_withNoCurrentSplit_createsVerticalSplitAndOpensFile() {
        sut.openFile(fileA)

        sut.openFileInSplit(fileB)

        XCTAssertEqual(sut.splitOrientation, .vertical, "Should create vertical split")
        XCTAssertEqual(sut.activePaneIndex, 1, "New pane should be active")
        XCTAssertEqual(sut.selectedFile, fileB, "New pane should show fileB")
    }

    func test_openInSplit_withExistingSplit_opensInInactivePane() {
        sut.openFile(fileA)
        sut.splitVertically() // pane 1 active, shows fileA

        sut.activePaneIndex = 0 // focus pane 0
        sut.openFileInSplit(fileC) // should open in other pane (pane 1)

        XCTAssertEqual(sut.activePaneIndex, 1, "Should focus the pane that received the file")
        XCTAssertEqual(sut.selectedFile, fileC, "Pane 1 should now show fileC")
    }

    // MARK: - Auto-close Split on Last Tab

    func test_closingLastTabInSplitPane_closesThatPane() {
        sut.openFile(fileA)
        sut.splitVertically()
        sut.openFile(fileB) // pane 1 has fileB as its only tab

        sut.closeTab(at: 0) // close the only tab in pane 1

        XCTAssertNil(sut.splitOrientation, "Split should be closed when last tab in a pane is closed")
    }

    func test_closingLastTabInPane1_keepsPane0Content() {
        sut.openFile(fileA) // pane 0 has fileA
        sut.splitVertically()
        sut.openFile(fileB) // pane 1 has fileB

        sut.closeTab(at: 0) // close pane 1's only tab

        XCTAssertEqual(sut.selectedFile, fileA, "After closing pane 1, pane 0's file should be active")
        XCTAssertEqual(sut.activePaneIndex, 0)
    }

    func test_closingLastTabInPane0_keepsPane1Content() {
        sut.openFile(fileA) // pane 0 has fileA
        sut.splitVertically()
        sut.openFile(fileB) // pane 1 has fileB

        sut.activePaneIndex = 0
        sut.closeTab(at: 0) // close pane 0's only tab

        XCTAssertNil(sut.splitOrientation, "Split should close")
        XCTAssertEqual(sut.selectedFile, fileB, "Former pane 1's file should survive")
    }

    // MARK: - Existing Behavior Preserved

    func test_singlePane_tabBehaviorUnchanged() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertNil(sut.splitOrientation)
    }

    func test_closeTab_inSplitPane_onlyAffectsActivePane() {
        sut.openFile(fileA)
        sut.splitVertically()
        sut.openFileInNewTab(fileB) // pane 1 now has fileA and fileB

        sut.closeTab(at: 0) // close first tab in pane 1

        sut.activePaneIndex = 0
        XCTAssertEqual(sut.tabs.count, 1, "Pane 0 should still have 1 tab")
    }
}
