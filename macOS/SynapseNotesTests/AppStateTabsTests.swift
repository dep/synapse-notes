import XCTest
@testable import Synapse

/// Tests for tab bar functionality: tracking multiple open files as tabs
final class AppStateTabsTests: XCTestCase {
    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!
    var fileB: URL!
    var fileC: URL!
    var currentTime: Date!

    override func setUp() {
        super.setUp()
        currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        sut = AppState(now: { [weak self] in self?.currentTime ?? Date() })

        // Create temp directory with test files
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        fileA = tempDir.appendingPathComponent("NoteA.md")
        fileB = tempDir.appendingPathComponent("NoteB.md")
        fileC = tempDir.appendingPathComponent("NoteC.md")

        // Create test files
        try! "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        try! "Content B".write(to: fileB, atomically: true, encoding: .utf8)
        try! "Content C".write(to: fileC, atomically: true, encoding: .utf8)

        sut.rootURL = tempDir
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Tab State

    func test_initialState_noTabs() {
        XCTAssertTrue(sut.tabs.isEmpty, "Should start with no tabs open")
        XCTAssertNil(sut.activeTabIndex, "Should have no active tab initially")
    }

    func test_openFile_addsToTabs() {
        sut.openFile(fileA)

        XCTAssertEqual(sut.tabs.count, 1, "Should have one tab after opening a file")
        XCTAssertEqual(sut.tabs[0], .file(fileA), "Tab should contain the opened file")
        XCTAssertEqual(sut.activeTabIndex, 0, "Active tab should be index 0")
    }

    func test_openFile_secondFile_replacesCurrentTab() {
        sut.openFile(fileA)
        sut.openFile(fileB)

        XCTAssertEqual(sut.tabs.count, 1, "Should still have one tab (replaced)")
        XCTAssertEqual(sut.tabs[0], .file(fileB), "Tab should contain the new file")
        XCTAssertEqual(sut.activeTabIndex, 0, "Active tab should still be index 0")
    }

    // MARK: - New Tab

    func test_openFileInNewTab_addsSecondTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        XCTAssertEqual(sut.tabs.count, 2, "Should have two tabs")
        XCTAssertEqual(sut.tabs[0], .file(fileA), "First tab should be fileA")
        XCTAssertEqual(sut.tabs[1], .file(fileB), "Second tab should be fileB")
        XCTAssertEqual(sut.activeTabIndex, 1, "Active tab should be the new tab (index 1)")
    }

    func test_openFileInNewTab_threeTabs() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        XCTAssertEqual(sut.tabs.count, 3, "Should have three tabs")
        XCTAssertEqual(sut.activeTabIndex, 2, "Active tab should be index 2")
    }

    func test_openFileInNewTab_savesDirtyActiveFileBeforeSwitching() throws {
        sut.openFile(fileA)
        sut.fileContent = "Unsaved edit in A"
        sut.isDirty = true

        sut.openFileInNewTab(fileB)

        let diskContent = try String(contentsOf: fileA, encoding: .utf8)
        XCTAssertEqual(diskContent, "Unsaved edit in A", "Opening a new tab should persist dirty edits from the current file")
        XCTAssertEqual(sut.selectedFile, fileB)
        XCTAssertFalse(sut.isDirty)
    }

    func test_openFileInNewTab_duplicateFile_makesExistingTabActive() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileA) // Try to open A again in new tab

        XCTAssertEqual(sut.tabs.count, 2, "Should still have only two tabs (no duplicates)")
        XCTAssertEqual(sut.tabs[0], .file(fileA), "First tab should be fileA")
        XCTAssertEqual(sut.tabs[1], .file(fileB), "Second tab should be fileB")
        XCTAssertEqual(sut.activeTabIndex, 0, "Active tab should switch to existing fileA tab (index 0)")
    }

    // MARK: - Closing Tabs

    func test_closeTab_removesTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.closeTab(at: 0)

        XCTAssertEqual(sut.tabs.count, 1, "Should have one tab after closing")
        XCTAssertEqual(sut.tabs[0], .file(fileB), "Remaining tab should be fileB")
        XCTAssertEqual(sut.activeTabIndex, 0, "Active tab should adjust to remaining tab")
    }

    func test_closeActiveTab_focusesLeftTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC) // Active is now index 2

        sut.closeTab(at: 2) // Close fileC

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.activeTabIndex, 1, "Should focus left tab (fileB at index 1)")
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_closeTab_whenLeftOfActive_focusesSameIndex() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC) // Active is now index 2

        sut.closeTab(at: 0) // Close fileA (left of active)

        XCTAssertEqual(sut.tabs.count, 2)
        XCTAssertEqual(sut.activeTabIndex, 1, "Active should adjust from 2 to 1")
        XCTAssertEqual(sut.tabs[1], .file(fileC))
    }

    func test_closeLastTab_clearsActiveTab() {
        sut.openFile(fileA)

        sut.closeTab(at: 0)

        XCTAssertTrue(sut.tabs.isEmpty, "Should have no tabs")
        XCTAssertNil(sut.activeTabIndex, "Should have no active tab")
    }

    // MARK: - Switching Tabs

    func test_switchTab_changesActiveTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.switchTab(to: 0)

        XCTAssertEqual(sut.activeTabIndex, 0, "Should switch to tab 0")
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_switchTab_restoresSavedCursorAndScrollStatePerTab() {
        sut.openFile(fileA)
        sut.pendingCursorRange = NSRange(location: 12, length: 4)
        sut.pendingScrollOffsetY = 144

        sut.openFileInNewTab(fileB)

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertNil(sut.pendingCursorRange)
        XCTAssertNil(sut.pendingScrollOffsetY)

        sut.pendingCursorRange = NSRange(location: 2, length: 0)
        sut.pendingScrollOffsetY = 32

        sut.switchTab(to: 0)

        XCTAssertEqual(sut.pendingCursorRange, NSRange(location: 12, length: 4))
        XCTAssertEqual(sut.pendingScrollOffsetY, 144)

        sut.pendingCursorRange = NSRange(location: 7, length: 0)
        sut.pendingScrollOffsetY = 72

        sut.switchTab(to: 1)

        XCTAssertEqual(sut.pendingCursorRange, NSRange(location: 2, length: 0))
        XCTAssertEqual(sut.pendingScrollOffsetY, 32)
    }

    func test_switchTab_invalidIndex_doesNothing() {
        sut.openFile(fileA)

        sut.switchTab(to: 5) // Invalid index

        XCTAssertEqual(sut.activeTabIndex, 0, "Should remain at tab 0")
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_switchTab_noTabs_doesNothing() {
        sut.switchTab(to: 0) // No tabs open

        XCTAssertNil(sut.activeTabIndex)
        XCTAssertNil(sut.selectedFile)
    }

    // MARK: - Keyboard Shortcuts

    func test_switchToTabShortcut_usesOneBasedIndex() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        sut.switchToTabShortcut(2)

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_switchToTabShortcut_nineSelectsLastTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        sut.switchToTabShortcut(9)

        XCTAssertEqual(sut.activeTabIndex, 2)
        XCTAssertEqual(sut.selectedFile, fileC)
    }

    func test_switchToTabShortcut_outOfRangeDoesNothing() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.switchToTabShortcut(3)

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_reopenClosedTab_restoresMostRecentlyClosedTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.closeTab(at: 1)
        sut.reopenLastClosedTab()

        XCTAssertEqual(sut.tabs, [.file(fileA), .file(fileB)])
        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_reopenClosedTab_reopensMultipleTabsInReverseCloseOrder() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        sut.closeTab(at: 2)
        sut.closeTab(at: 1)

        sut.reopenLastClosedTab()
        XCTAssertEqual(sut.tabs, [.file(fileA), .file(fileB)])
        XCTAssertEqual(sut.selectedFile, fileB)

        sut.reopenLastClosedTab()
        XCTAssertEqual(sut.tabs, [.file(fileA), .file(fileB), .file(fileC)])
        XCTAssertEqual(sut.selectedFile, fileC)
    }

    func test_reopenClosedTab_withNoClosedTabs_doesNothing() {
        sut.openFile(fileA)

        sut.reopenLastClosedTab()

        XCTAssertEqual(sut.tabs, [.file(fileA)])
        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_switchToPreviousTab_movesLeft() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        sut.switchToPreviousTab()

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_switchToNextTab_movesRight() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)
        sut.switchTab(to: 0)

        sut.switchToNextTab()

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_switchToPreviousTab_atFirstTab_doesNothing() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.switchTab(to: 0)

        sut.switchToPreviousTab()

        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_switchToNextTab_atLastTab_doesNothing() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)

        sut.switchToNextTab()

        XCTAssertEqual(sut.activeTabIndex, 1)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_closeOtherTabs_keepsOnlyActiveTab() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)
        sut.switchTab(to: 1)

        sut.closeOtherTabs()

        XCTAssertEqual(sut.tabs, [.file(fileB)])
        XCTAssertEqual(sut.activeTabIndex, 0)
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    func test_closeOtherTabs_reopenRestoresClosedTabsInReverseOrder() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)
        sut.switchTab(to: 1)

        sut.closeOtherTabs()

        sut.reopenLastClosedTab()
        XCTAssertEqual(sut.tabs, [.file(fileB), .file(fileC)])
        XCTAssertEqual(sut.selectedFile, fileC)

        sut.reopenLastClosedTab()
        XCTAssertEqual(sut.tabs, [.file(fileA), .file(fileB), .file(fileC)])
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_cycleMostRecentTabs_togglesBetweenTwoMostRecentTabs() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)
        sut.switchTab(to: 0)

        sut.cycleMostRecentTabs()
        XCTAssertEqual(sut.selectedFile, fileC)

        sut.cycleMostRecentTabs()
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_cycleMostRecentTabs_ignoresLessRecentTabsWhenToggling() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)
        sut.switchTab(to: 0)

        sut.cycleMostRecentTabs()
        XCTAssertEqual(sut.selectedFile, fileC)

        sut.cycleMostRecentTabs()
        XCTAssertEqual(sut.selectedFile, fileA)
    }
}
