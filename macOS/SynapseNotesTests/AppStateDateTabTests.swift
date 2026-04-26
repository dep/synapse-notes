import XCTest
@testable import Synapse

/// Tests for date-based tab functionality: opening dates in new tabs.
/// Mirrors the pattern used for tags (openTagInNewTab).
final class AppStateDateTabTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var calendar: Calendar!
    var testDate: Date!

    override func setUp() {
        super.setUp()
        sut = AppState()
        calendar = Calendar.current

        // Create a fixed test date: 2024-01-15
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        testDate = calendar.date(from: components)

        // Create temp directory
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Opening Date Tabs

    func test_openDateInNewTab_withNoTabs_addsDateTab() {
        sut.openDateInNewTab(testDate)

        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.tabs[0], .date(testDate))
    }

    func test_openDateInNewTab_setsActiveTabIndex() {
        sut.openDateInNewTab(testDate)

        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    func test_openDateInNewTab_activeTabIsDate() {
        sut.openDateInNewTab(testDate)

        XCTAssertTrue(sut.activeTab?.isDate == true)
        XCTAssertEqual(sut.activeTab?.dateValue, testDate)
    }

    func test_openDateInNewTab_clearsSelectedFile() {
        // Create a file to open first
        let fileURL = tempDir.appendingPathComponent("TestNote.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openFile(fileURL)
        XCTAssertNotNil(sut.selectedFile)

        sut.openDateInNewTab(testDate)

        XCTAssertNil(sut.selectedFile)
    }

    func test_openDateInNewTab_clearsFileContent() {
        let fileURL = tempDir.appendingPathComponent("TestNote.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openFile(fileURL)
        XCTAssertFalse(sut.fileContent.isEmpty)

        sut.openDateInNewTab(testDate)

        XCTAssertEqual(sut.fileContent, "")
    }

    func test_openDateInNewTab_clearsDirtyFlag() {
        let fileURL = tempDir.appendingPathComponent("TestNote.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openFile(fileURL)
        sut.fileContent = "Unsaved edit"
        sut.isDirty = true

        sut.openDateInNewTab(testDate)

        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - Deduplication

    func test_openDateInNewTab_whenAlreadyOpen_switchesToExistingTab() {
        // Create a file first
        let fileURL = tempDir.appendingPathComponent("Test.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openDateInNewTab(testDate)  // tab 0
        sut.openFileInNewTab(fileURL)  // tab 1

        sut.switchTab(to: 0)  // Go back to date tab

        sut.openDateInNewTab(testDate)  // Should reuse, not create new

        XCTAssertEqual(sut.tabs.count, 2, "Should not add a second date tab")
        XCTAssertEqual(sut.activeTabIndex, 0, "Should switch to the existing date tab")
        XCTAssertEqual(sut.activeTab, .date(testDate))
    }

    func test_openDateInNewTab_differentDates_createSeparateTabs() {
        let date1 = testDate!
        let date2 = calendar.date(byAdding: .day, value: 1, to: date1)!

        sut.openDateInNewTab(date1)
        sut.openDateInNewTab(date2)

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .date(date1))
        XCTAssertEqual(sut.tabs[1], .date(date2))
    }

    func test_openDateInNewTab_calledTwice_sameDate_onlyOneTabExists() {
        sut.openDateInNewTab(testDate)
        sut.openDateInNewTab(testDate)

        let dateTabCount = sut.tabs.filter { $0 == .date(testDate) }.count
        XCTAssertEqual(dateTabCount, 1, "Only one date tab should ever exist for the same date")
    }

    // MARK: - Date Tab with Other Tabs

    func test_openDateInNewTab_appendsAfterFileTabs() {
        let fileURL = tempDir.appendingPathComponent("TestNote.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openFile(fileURL)
        sut.openFileInNewTab(tempDir.appendingPathComponent("TestNote2.md"))

        sut.openDateInNewTab(testDate)

        XCTAssertEqual(sut.tabs.count, 3)
        XCTAssertEqual(sut.tabs[2], .date(testDate))
        XCTAssertEqual(sut.activeTabIndex, 2)
    }

    func test_openDateInNewTab_afterTagTab_appendsCorrectly() {
        sut.openTagInNewTab("work")

        sut.openDateInNewTab(testDate)

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.tabs[0], .tag("work"))
        XCTAssertEqual(sut.tabs[1], .date(testDate))
        XCTAssertEqual(sut.activeTabIndex, 1)
    }

    // MARK: - Closing and Reopening

    func test_closeDateTab_removesItFromTabs() {
        let fileURL = tempDir.appendingPathComponent("TestNote.md")
        try! "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()

        sut.openFile(fileURL)
        sut.openDateInNewTab(testDate)  // tab 1

        sut.closeTab(at: 1)

        XCTAssertFalse(sut.tabs.contains(.date(testDate)))
        XCTAssertEqual(sut.tabs.count, 1)
        XCTAssertEqual(sut.activeTabIndex, 0)
    }

    func test_openDateInNewTab_afterClosingPrevious_createsNewDateTab() {
        sut.openDateInNewTab(testDate)
        sut.closeTab(at: 0)

        sut.openDateInNewTab(testDate)

        XCTAssertTrue(sut.tabs.contains(.date(testDate)))
        XCTAssertEqual(sut.activeTab, .date(testDate))
    }

    // MARK: - Tab Type Helpers

    func test_dateTabItem_isDate_returnsTrue() {
        sut.openDateInNewTab(testDate)
        XCTAssertTrue(sut.activeTab?.isDate == true)
    }

    func test_dateTabItem_isFile_returnsFalse() {
        sut.openDateInNewTab(testDate)
        XCTAssertFalse(sut.activeTab?.isFile == true)
    }

    func test_dateTabItem_isTag_returnsFalse() {
        sut.openDateInNewTab(testDate)
        XCTAssertFalse(sut.activeTab?.isTag == true)
    }

    func test_dateTabItem_isGraph_returnsFalse() {
        sut.openDateInNewTab(testDate)
        XCTAssertFalse(sut.activeTab?.isGraph == true)
    }

    func test_dateTabItem_displayName_isISOFormat() {
        sut.openDateInNewTab(testDate)
        XCTAssertEqual(sut.activeTab?.displayName, "2024-01-15")
    }

    // MARK: - TabItem Equality

    func test_dateTabItem_equality_sameDate() {
        let tab1 = TabItem.date(testDate)
        let tab2 = TabItem.date(testDate)

        XCTAssertEqual(tab1, tab2)
    }

    func test_dateTabItem_equality_differentDates() {
        let date1 = testDate!
        let date2 = calendar.date(byAdding: .day, value: 1, to: date1)!

        let tab1 = TabItem.date(date1)
        let tab2 = TabItem.date(date2)

        XCTAssertNotEqual(tab1, tab2)
    }

    func test_dateTabItem_hashValue_sameForSameDate() {
        let tab1 = TabItem.date(testDate)
        let tab2 = TabItem.date(testDate)

        XCTAssertEqual(tab1.hashValue, tab2.hashValue)
    }
}
