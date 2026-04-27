import XCTest
@testable import Synapse

/// Tests for exitVault: verifies complete state reset including tabs, navigation,
/// file lists, git state, and command-palette state.
final class AppStateExitVaultFullTests: XCTestCase {

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

        fileA = tempDir.appendingPathComponent("a.md")
        fileB = tempDir.appendingPathComponent("b.md")
        fileC = tempDir.appendingPathComponent("c.md")
        FileManager.default.createFile(atPath: fileA.path, contents: "A".data(using: .utf8))
        FileManager.default.createFile(atPath: fileB.path, contents: "B".data(using: .utf8))
        FileManager.default.createFile(atPath: fileC.path, contents: "C".data(using: .utf8))

        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Tabs cleared

    func test_exitVault_clearsTabs() {
        sut.openFile(fileA)
        sut.openFileInNewTab(fileB)
        sut.openFileInNewTab(fileC)

        sut.exitVault()

        XCTAssertTrue(sut.tabs.isEmpty, "tabs should be empty after exitVault")
        XCTAssertNil(sut.activeTabIndex, "activeTabIndex should be nil after exitVault")
    }

    // MARK: - Navigation reset

    func test_exitVault_resetsNavigationHistory() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.openFile(fileC)
        XCTAssertTrue(sut.canGoBack, "precondition: canGoBack should be true before exit")

        sut.exitVault()

        XCTAssertFalse(sut.canGoBack, "canGoBack should be false after exitVault")
        XCTAssertFalse(sut.canGoForward, "canGoForward should be false after exitVault")
    }

    func test_exitVault_afterBackNavigation_resetsForwardState() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        XCTAssertTrue(sut.canGoForward, "precondition: canGoForward should be true before exit")

        sut.exitVault()

        XCTAssertFalse(sut.canGoForward, "canGoForward should be false after exitVault")
        XCTAssertFalse(sut.canGoBack, "canGoBack should be false after exitVault")
    }

    // MARK: - File lists cleared

    func test_exitVault_clearsAllFiles() {
        sut.refreshAllFiles()
        XCTAssertFalse(sut.allFiles.isEmpty, "precondition: allFiles should have entries before exit")

        sut.exitVault()

        XCTAssertTrue(sut.allFiles.isEmpty, "allFiles should be empty after exitVault")
        XCTAssertTrue(sut.allProjectFiles.isEmpty, "allProjectFiles should be empty after exitVault")
    }

    /// Bumping `scanGeneration` on exit invalidates async `rebuildFileLists` work so a scan
    /// that was queued before exit cannot repopulate `allFiles` after `rootURL` is nil.
    func test_exitVault_bumpsScanGeneration_toInvalidateInFlightScans() {
        let generationBeforeExit = sut.scanGeneration
        sut.exitVault()
        XCTAssertEqual(sut.scanGeneration, generationBeforeExit + 1)
    }

    /// Bumping `gitDateCacheGeneration` on exit invalidates async `refreshGitDateCache` work so
    /// a slow `git log` cannot repopulate `gitDateCache` after we cleared it (wrong-vault paths).
    func test_exitVault_bumpsGitDateCacheGeneration_toInvalidateInFlightRefresh() {
        let generationBeforeExit = sut.gitDateCacheGeneration
        sut.exitVault()
        XCTAssertEqual(sut.gitDateCacheGeneration, generationBeforeExit + 1)
    }

    // MARK: - Git state reset

    func test_exitVault_resetsGitState() {
        // Manually set git state to non-default values to simulate an open vault
        sut.gitBranch = "feature/my-branch"
        sut.gitAheadCount = 3
        sut.gitSyncStatus = .idle

        sut.exitVault()

        XCTAssertEqual(sut.gitBranch, "main", "gitBranch should reset to 'main' after exitVault")
        XCTAssertEqual(sut.gitAheadCount, 0, "gitAheadCount should reset to 0 after exitVault")
        if case .notGitRepo = sut.gitSyncStatus {
            // expected
        } else {
            XCTFail("gitSyncStatus should be .notGitRepo after exitVault, got \(sut.gitSyncStatus)")
        }
    }

    // MARK: - Command palette and template state

    func test_exitVault_resetsCommandPaletteMode() {
        sut.commandPaletteMode = .templates

        sut.exitVault()

        if case .files = sut.commandPaletteMode {
            // expected
        } else {
            XCTFail("commandPaletteMode should reset to .files after exitVault")
        }
    }

    func test_exitVault_clearsPendingTemplateRename() {
        sut.openFile(fileA)
        sut.pendingTemplateRename = TemplateRenameRequest(url: fileA)

        sut.exitVault()

        XCTAssertNil(sut.pendingTemplateRename, "pendingTemplateRename should be nil after exitVault")
    }

    // MARK: - Core state reset

    func test_exitVault_clearsRootURLAndSelectedFile() {
        sut.openFile(fileA)

        sut.exitVault()

        XCTAssertNil(sut.rootURL, "rootURL should be nil after exitVault")
        XCTAssertNil(sut.selectedFile, "selectedFile should be nil after exitVault")
        XCTAssertEqual(sut.fileContent, "", "fileContent should be empty after exitVault")
        XCTAssertFalse(sut.isDirty, "isDirty should be false after exitVault")
    }
}
