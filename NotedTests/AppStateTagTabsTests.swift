import XCTest
@testable import Noted

/// Tests for the tag tab feature: opening tags as first-class tabs.
/// Tag tabs differ from file tabs — they have no associated file, clear `selectedFile`,
/// and display with a `#` prefix.
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

    // MARK: - Opening tag tabs

    func test_openTagInNewTab_addsTagTabAtIndex0() {
        sut.openTagInNewTab("swift")

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .tag("swift"))
        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    func test_openTagInNewTab_clearsSelectedFile() {
        sut.openFile(fileA)
        sut.openTagInNewTab("swift")

        XCTAssertNil(sut.selectedFile, "Tag tab should clear the selected file")
    }

    func test_openTagInNewTab_clearsFileContent() {
        sut.openFile(fileA)
        sut.openTagInNewTab("swift")

        XCTAssertEqual(sut.fileContent, "", "Tag tab should clear file content")
    }

    func test_openTagInNewTab_doesNotCarryOverDirtyState() {
        sut.openFile(fileA)
        sut.isDirty = true
        sut.openTagInNewTab("swift")

        XCTAssertFalse(sut.isDirty, "Tag tab should not inherit the dirty flag")
    }

    func test_openTagInNewTab_afterFileTab_isAppendedAfterIt() {
        sut.openFile(fileA)
        sut.openTagInNewTab("swift")

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .file(fileA))
        XCTAssertEqual(sut.tabs[1], .tag("swift"))
        XCTAssertEqual(sut.activeTabIndex, 1)
    }

    func test_openTagInNewTab_multipleDistinctTags_allAdded() {
        sut.openTagInNewTab("swift")
        sut.openTagInNewTab("xcode")
        sut.openTagInNewTab("testing")

        XCTAssertEqual(sut.tabs.count, 3)
        XCTAssertEqual(sut.tabs[0], .tag("swift"))
        XCTAssertEqual(sut.tabs[1], .tag("xcode"))
        XCTAssertEqual(sut.tabs[2], .tag("testing"))
    }

    func test_openTagInNewTab_sameTagTwice_switchesToExistingTab() {
        sut.openTagInNewTab("swift")
        sut.openTagInNewTab("xcode")
        sut.openTagInNewTab("swift") // already open

        XCTAssertEqual(sut.tabs.count, 2, "Should not add a duplicate tag tab")
        XCTAssertEqual(sut.activeTabIndex, 0, "Should switch to the existing 'swift' tab")
    }

    // MARK: - activeTab computed property

    func test_activeTab_withFileTabActive_returnsFileItem() {
        sut.openFile(fileA)
        XCTAssertEqual(sut.activeTab, .file(fileA))
    }

    func test_activeTab_withTagTabActive_returnsTagItem() {
        sut.openTagInNewTab("swift")
        XCTAssertEqual(sut.activeTab, .tag("swift"))
    }

    func test_activeTab_withNoTabs_returnsNil() {
        XCTAssertNil(sut.activeTab)
    }

    func test_activeTab_afterSwitchingToTagTab_updatesToTagItem() {
        sut.openFile(fileA)
        sut.openTagInNewTab("swift")
        sut.switchTab(to: 0)

        XCTAssertEqual(sut.activeTab, .file(fileA))

        sut.switchTab(to: 1)
        XCTAssertEqual(sut.activeTab, .tag("swift"))
    }

    // MARK: - Closing tag tabs

    func test_closeTagTab_removesItFromTabs() {
        sut.openTagInNewTab("swift")
        sut.openTagInNewTab("xcode")

        sut.closeTab(at: 0) // close "swift"

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .tag("xcode"))
    }

    func test_closeTagTab_whenLastTab_clearsActiveTabIndex() {
        sut.openTagInNewTab("swift")
        sut.closeTab(at: 0)

        XCTAssertTrue(sut.tabs.isEmpty)
        XCTAssertNil(sut.activeTabIndex)
    }

    // MARK: - Reopening closed tag tabs

    func test_reopenLastClosedTab_restoresTagTab() {
        sut.openTagInNewTab("swift")
        sut.closeTab(at: 0)

        sut.reopenLastClosedTab()

        XCTAssertEqual(sut.tabs, [.tag("swift")])
        XCTAssertEqual(sut.activeTabIndex, 0)
    }
}
