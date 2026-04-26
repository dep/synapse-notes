import XCTest
@testable import Synapse

/// Tests for the graph tab: opening, deduplication, state clearing, and interaction
/// with other tab types. `openGraphTab()` is the sole entry-point for the global
/// vault graph view — if it misbehaves the graph feature is unreachable or
/// pollutes the tab bar with duplicates.
final class AppStateGraphTabTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!
    var fileB: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        fileA = tempDir.appendingPathComponent("NoteA.md")
        fileB = tempDir.appendingPathComponent("NoteB.md")
        try! "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        try! "Content B".write(to: fileB, atomically: true, encoding: .utf8)

        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Opening a graph tab from an empty state

    func test_openGraphTab_withNoTabs_addsGraphTab() {
        sut.openGraphTab()

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .graph)
    }

    func test_openGraphTab_setsActiveTabIndex() {
        sut.openGraphTab()

        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    func test_openGraphTab_activeTabIsGraph() {
        sut.openGraphTab()

        XCTAssertEqual(sut.activeTab, .graph)
    }

    // MARK: - State clearing when graph tab opens

    func test_openGraphTab_clearsSelectedFile() {
        sut.openFile(fileA)
        XCTAssertNotNil(sut.selectedFile)

        sut.openGraphTab()

        XCTAssertNil(sut.selectedFile)
    }

    func test_openGraphTab_clearsFileContent() {
        sut.openFile(fileA)
        XCTAssertFalse(sut.fileContent.isEmpty)

        sut.openGraphTab()

        XCTAssertEqual(sut.fileContent, "")
    }

    func test_openGraphTab_clearsDirtyFlag() {
        sut.openFile(fileA)
        sut.fileContent = "Unsaved edit"
        sut.isDirty = true

        sut.openGraphTab()

        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - Deduplication

    func test_openGraphTab_whenAlreadyOpen_switchesToExistingTab() {
        sut.openFile(fileA)       // tab 0: fileA
        sut.openGraphTab()        // tab 1: graph
        sut.switchTab(to: 0)      // switch back to fileA

        sut.openGraphTab()        // should reuse existing graph tab

        XCTAssertEqual(sut.tabs.count, 2, "Should not add a second graph tab")
        XCTAssertEqual(sut.activeTabIndex, 1, "Should switch to the existing graph tab")
        XCTAssertEqual(sut.activeTab, .graph)
    }

    func test_openGraphTab_calledTwice_onlyOneGraphTabExists() {
        sut.openGraphTab()
        sut.openGraphTab()

        let graphTabCount = sut.tabs.filter { $0 == .graph }.count
        XCTAssertEqual(graphTabCount, 1, "Only one graph tab should ever exist")
    }

    // MARK: - Graph tab with other tabs present

    func test_openGraphTab_appendsAfterFileTabs() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.openGraphTab()

        XCTAssertEqual(sut.tabs.count, 3)
        XCTAssertEqual(sut.tabs[2], .graph)
        XCTAssertEqual(sut.activeTabIndex, 2)
    }

    func test_openGraphTab_afterTagTab_appendsCorrectly() {
        sut.openTagInNewTab("work")

        sut.openGraphTab()

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .tag("work"))
        XCTAssertEqual(sut.tabs[1], .graph)
        XCTAssertEqual(sut.activeTabIndex, 1)
    }

    // MARK: - Closing and reopening the graph tab

    func test_closeGraphTab_removesItFromTabs() {
        sut.openFile(fileA)
        sut.openGraphTab()    // tab 1

        sut.closeTab(at: 1)

        XCTAssertFalse(sut.tabs.contains(.graph))
        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_openGraphTab_afterClosingPrevious_createsNewGraphTab() {
        sut.openFile(fileA)
        sut.openGraphTab()
        sut.closeTab(at: 1)

        sut.openGraphTab()

        XCTAssertTrue(sut.tabs.contains(.graph))
        XCTAssertEqual(sut.activeTab, .graph)
    }

    // MARK: - Tab type helpers on the .graph case

    func test_graphTabItem_isGraph_returnsTrue() {
        sut.openGraphTab()
        XCTAssertTrue(sut.activeTab?.isGraph == true)
    }

    func test_graphTabItem_isFile_returnsFalse() {
        sut.openGraphTab()
        XCTAssertFalse(sut.activeTab?.isFile == true)
    }

    func test_graphTabItem_isTag_returnsFalse() {
        sut.openGraphTab()
        XCTAssertFalse(sut.activeTab?.isTag == true)
    }

    func test_graphTabItem_displayName_isGraph() {
        sut.openGraphTab()
        XCTAssertEqual(sut.activeTab?.displayName, "Graph")
    }
}
