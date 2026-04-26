import XCTest
@testable import Synapse

/// Tests for tag tab functionality: opening, switching, closing, and MRU cycling with tag tabs
final class AppStateTagTabsTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileA = tempDir.appendingPathComponent("NoteA.md")
        try! "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - TabItem

    func test_tabItem_fileDisplayName_isFilename() {
        let item = TabItem.file(fileA)
        XCTAssertEqual(item.displayName, "NoteA.md")
    }

    func test_tabItem_tagDisplayName_hasPrefixHash() {
        let item = TabItem.tag("work")
        XCTAssertEqual(item.displayName, "#work")
    }

    func test_tabItem_isFile_trueForFile() {
        XCTAssertTrue(TabItem.file(fileA).isFile)
        XCTAssertFalse(TabItem.tag("work").isFile)
    }

    func test_tabItem_isTag_trueForTag() {
        XCTAssertTrue(TabItem.tag("work").isTag)
        XCTAssertFalse(TabItem.file(fileA).isTag)
    }

    func test_tabItem_fileURL_returnsURLForFileTab() {
        XCTAssertEqual(TabItem.file(fileA).fileURL, fileA)
        XCTAssertNil(TabItem.tag("work").fileURL)
    }

    func test_tabItem_tagName_returnsNameForTagTab() {
        XCTAssertEqual(TabItem.tag("work").tagName, "work")
        XCTAssertNil(TabItem.file(fileA).tagName)
    }

    // MARK: - activeTab

    func test_activeTab_nilWhenNoTabs() {
        XCTAssertNil(sut.activeTab)
    }

    func test_activeTab_returnsCurrentTabItem() {
        sut.openFile(fileA)
        XCTAssertEqual(sut.activeTab, .file(fileA))
    }

    func test_activeTab_returnsTagTabWhenTagIsActive() {
        sut.openTagInNewTab("work")
        XCTAssertEqual(sut.activeTab, .tag("work"))
    }

    // MARK: - openTagInNewTab

    func test_openTagInNewTab_addsTagTab() {
        sut.openTagInNewTab("work")

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .tag("work"))
        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    func test_openTagInNewTab_clearsSelectedFileAndContent() {
        sut.openFile(fileA)
        sut.openTagInNewTab("work")

        XCTAssertNil(sut.selectedFile)
        XCTAssertEqual(sut.fileContent, "")
        XCTAssertFalse(sut.isDirty)
    }

    func test_openTagInNewTab_switchesToExistingTabIfAlreadyOpen() {
        sut.openFile(fileA)
        sut.openTagInNewTab("work")
        sut.openTagInNewTab("work") // open again

        XCTAssertEqual(sut.tabs.count, 2, "Should not add duplicate tag tab")
        XCTAssertEqual(sut.activeTabIndex, 1)
    }

    func test_openTagInNewTab_mixedWithFileTabs() {
        sut.openFile(fileA)
        sut.openTagInNewTab("work")

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .file(fileA))
        XCTAssertEqual(sut.tabs[1], .tag("work"))
        XCTAssertEqual(sut.activeTabIndex, 1)
    }

    func test_openTagInNewTab_multipleDistinctTags() {
        sut.openTagInNewTab("work")
        sut.openTagInNewTab("ideas")

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .tag("work"))
        XCTAssertEqual(sut.tabs[1], .tag("ideas"))
    }

    // MARK: - Closing tag tabs

    func test_closeTagTab_removesItAndFocusesNeighbor() {
        sut.openFile(fileA)
        sut.openTagInNewTab("work")

        sut.closeTab(at: 1)

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .file(fileA))
        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_closeTagTab_whenLastTab_clearsState() {
        sut.openTagInNewTab("work")

        sut.closeTab(at: 0)

        XCTAssertTrue(sut.tabs.isEmpty)
        XCTAssertNil(sut.activeTabIndex)
        XCTAssertNil(sut.selectedFile)
    }

    // MARK: - Reopening closed tag tabs

    func test_reopenLastClosedTab_restoresTagTab() {
        sut.openTagInNewTab("work")
        sut.closeTab(at: 0)

        sut.reopenLastClosedTab()

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .tag("work"))
        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    // MARK: - MRU cycling with tag tabs

    func test_cycleMostRecentTabs_cyclesBetweenFileAndTagTab() {
        sut.openFile(fileA)       // MRU: [A]
        sut.openTagInNewTab("work") // MRU: [work, A]
        sut.switchTab(to: 0)       // MRU: [A, work]

        sut.cycleMostRecentTabs()

        XCTAssertEqual(sut.activeTab, .tag("work"))
    }

    func test_cycleMostRecentTabs_togglingBetweenFileAndTagTab() {
        sut.openFile(fileA)
        sut.openTagInNewTab("work")
        sut.switchTab(to: 0) // switch to fileA

        sut.cycleMostRecentTabs() // → work
        XCTAssertEqual(sut.activeTab, .tag("work"))

        sut.cycleMostRecentTabs() // → fileA
        XCTAssertEqual(sut.activeTab, .file(fileA))
    }
}
