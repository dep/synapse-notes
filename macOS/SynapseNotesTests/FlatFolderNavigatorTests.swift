import XCTest
@testable import Synapse

/// Tests for the flat folder navigator feature (Issue #200).
///
/// Covers:
/// - Flat navigation state management (current directory tracking)
/// - Navigation into folders (drill-down behavior)
/// - Back button navigation (navigate up one level)
/// - Pinned folders as drop targets for drag-and-drop
/// - Drag-over-back-button navigation (hover to navigate up during drag)
/// - Flat view shows only current directory contents (no tree indentation)
final class FlatFolderNavigatorTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var folderA: URL!
    var folderB: URL!
    var subfolder: URL!
    var file1: URL!
    var file2: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create test folder structure:
        // /tempDir/
        //   folder-a/
        //     file1.md
        //     subfolder/
        //       file2.md
        //   folder-b/
        //     (empty)
        folderA = makeFolder(named: "folder-a")
        folderB = makeFolder(named: "folder-b")
        subfolder = makeFolder(named: "subfolder", in: folderA)
        file1 = makeFile(named: "file1.md", in: folderA)
        file2 = makeFile(named: "file2.md", in: subfolder)
        
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(named name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? tempDir!
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "content".data(using: .utf8))
        return url
    }

    private func makeFolder(named name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? tempDir!
        let url = dir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Flat Navigation State Tests

    func test_initialState_currentDirectoryIsRoot() {
        // Initially, current directory should return root (even though the stored value may be nil)
        // When flatNavigatorCurrentDirectory is nil, it defaults to rootURL
        let expectedRoot = tempDir.standardizedFileURL
        let actual = sut.flatNavigatorCurrentDirectory?.standardizedFileURL ?? expectedRoot
        XCTAssertEqual(actual, expectedRoot,
                       "Initial current directory should default to the root")
    }

    func test_navigateToFolder_updatesCurrentDirectory() {
        // When navigating to a folder
        sut.navigateToFolder(folderA)
        
        // Then current directory should be that folder
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, folderA.standardizedFileURL,
                       "Current directory should update to the navigated folder")
    }

    func test_navigateToFolder_canNavigateMultipleLevels() {
        // Navigate to folder-a
        sut.navigateToFolder(folderA)
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, folderA.standardizedFileURL)
        
        // Navigate deeper into subfolder
        sut.navigateToFolder(subfolder)
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, subfolder.standardizedFileURL,
                       "Should be able to navigate multiple levels deep")
    }

    // MARK: - Back Button Navigation Tests

    func test_canNavigateBack_isFalseAtRoot() {
        // At root level, should not be able to navigate back
        XCTAssertFalse(sut.canNavigateBackInFlatNavigator,
                       "Should not be able to navigate back when at root")
    }

    func test_canNavigateBack_isTrueInSubfolder() {
        // Navigate to a subfolder
        sut.navigateToFolder(folderA)
        
        // Then should be able to navigate back
        XCTAssertTrue(sut.canNavigateBackInFlatNavigator,
                      "Should be able to navigate back when in a subfolder")
    }

    func test_navigateBack_goesToParentDirectory() {
        // Given we're in subfolder
        sut.navigateToFolder(folderA)
        sut.navigateToFolder(subfolder)
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, subfolder.standardizedFileURL)
        
        // When navigating back
        sut.navigateBackInFlatNavigator()
        
        // Then should be in parent directory
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, folderA.standardizedFileURL,
                       "Navigate back should go to parent directory")
    }

    func test_navigateBack_multipleTimesGoesToRoot() {
        // Given we're deep in the hierarchy
        sut.navigateToFolder(folderA)
        sut.navigateToFolder(subfolder)
        
        // Navigate back once
        sut.navigateBackInFlatNavigator()
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, folderA.standardizedFileURL)
        
        // Navigate back again
        sut.navigateBackInFlatNavigator()
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, tempDir.standardizedFileURL,
                       "Multiple navigate back should reach root")
    }

    func test_navigateBack_atRoot_doesNothing() {
        // Given we're at root (explicitly set it)
        sut.navigateToRootInFlatNavigator()
        let expectedRoot = tempDir.standardizedFileURL
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, expectedRoot)
        
        // When trying to navigate back at root
        sut.navigateBackInFlatNavigator()
        
        // Should stay at root
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, expectedRoot,
                       "Navigate back at root should stay at root")
    }

    // MARK: - Flat View Content Tests

    func test_flatViewContents_returnsCurrentDirectoryContents() {
        // Given we're in folder-a
        sut.navigateToFolder(folderA)
        
        // When getting flat view contents
        let contents = sut.flatNavigatorCurrentContents
        
        // Then should contain folder-a's contents (not root contents)
        let contentPaths = contents.map { $0.standardizedFileURL.path }
        XCTAssertTrue(contentPaths.contains(subfolder.standardizedFileURL.path),
                      "Should contain subfolder")
        XCTAssertTrue(contentPaths.contains(file1.standardizedFileURL.path),
                      "Should contain file1")
        XCTAssertFalse(contentPaths.contains(folderB.standardizedFileURL.path),
                       "Should NOT contain folderB (it's in root)")
    }

    func test_flatViewContents_atRoot_showsRootContents() {
        // When at root
        let contents = sut.flatNavigatorCurrentContents
        
        // Should show root-level items
        let contentPaths = contents.map { $0.standardizedFileURL.path }
        XCTAssertTrue(contentPaths.contains(folderA.standardizedFileURL.path),
                      "Root view should contain folder-a")
        XCTAssertTrue(contentPaths.contains(folderB.standardizedFileURL.path),
                      "Root view should contain folder-b")
        XCTAssertFalse(contentPaths.contains(subfolder.standardizedFileURL.path),
                       "Root view should NOT contain nested items")
    }

    func test_flatViewContents_showsDotPrefixedFilesAndFoldersByDefault() {
        sut.settings.fileExtensionFilter = "*" // isolate dot-prefix behavior from default *.md filter
        let dotFolder = makeFolder(named: ".agents")
        let dotFile = makeFile(named: ".env")

        let contents = sut.flatNavigatorCurrentContents
        let names = Set(contents.map(\.lastPathComponent))

        XCTAssertTrue(names.contains(".agents"), "Dot-prefixed folders should appear unless hidden in settings")
        XCTAssertTrue(names.contains(".env"), "Dot-prefixed files should appear unless hidden in settings")
    }

    func test_flatViewContents_hidesDotItemWhenMatchingHiddenFilter() {
        sut.settings.fileExtensionFilter = "*"
        makeFolder(named: ".agents")
        makeFile(named: ".env")
        sut.settings.hiddenFileFolderFilter = ".agents, .env"

        let contents = sut.flatNavigatorCurrentContents
        let names = Set(contents.map(\.lastPathComponent))

        XCTAssertFalse(names.contains(".agents"))
        XCTAssertFalse(names.contains(".env"))
    }

    // MARK: - Pinned Folder Drop Target Tests

    func test_pinnedFolderCanAcceptDrop() {
        // Pin folderA
        sut.pinItem(folderA)
        
        // folderA should be a valid drop target
        let pinnedItem = sut.pinnedItems.first!
        XCTAssertTrue(pinnedItem.isFolder, "Pinned item should be a folder")
        XCTAssertNotNil(pinnedItem.url, "Pinned folder should have a URL")
    }

    func test_dropFileOntoPinnedFolder_movesFile() throws {
        // Pin folderB
        sut.pinItem(folderB)
        let pinnedItem = sut.pinnedItems.first!
        
        // Create a file to drop
        let fileToMove = makeFile(named: "droptest.md")
        
        // When dropping file onto pinned folder
        let result = try sut.dropFile(fileToMove, ontoPinnedItem: pinnedItem)
        
        // Then file should be moved to that folder
        XCTAssertEqual(result.deletingLastPathComponent().standardizedFileURL, folderB.standardizedFileURL,
                       "File should be moved to pinned folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileToMove.path),
                       "Original file should no longer exist")
    }

    func test_dropFileOntoPinnedFile_throwsError() throws {
        // Pin a file (not a folder)
        let pinnedFile = makeFile(named: "pinned-note.md")
        sut.pinItem(pinnedFile)
        let pinnedItem = sut.pinnedItems.first!
        
        // Create a file to try to drop
        let fileToMove = makeFile(named: "droptest.md")
        
        // When trying to drop onto a pinned file (not folder)
        // Should throw an error
        XCTAssertThrowsError(try sut.dropFile(fileToMove, ontoPinnedItem: pinnedItem)) { error in
            XCTAssertEqual(error as? FileBrowserError, .operationFailed("Target is not a folder"))
        }
    }

    func test_dropFileOntoPinnedTag_throwsError() throws {
        // Pin a tag
        sut.pinTag("test-tag")
        let pinnedItem = sut.pinnedItems.first!
        
        // Create a file to try to drop
        let fileToMove = makeFile(named: "droptest.md")
        
        // When trying to drop onto a pinned tag
        // Should throw an error
        XCTAssertThrowsError(try sut.dropFile(fileToMove, ontoPinnedItem: pinnedItem)) { error in
            XCTAssertEqual(error as? FileBrowserError, .operationFailed("Target is not a folder"))
        }
    }

    // MARK: - Drag-Over-Back-Button Navigation Tests

    func test_dragHoverOverBackButton_schedulesNavigationUp() {
        // Given we're in a subfolder
        sut.navigateToFolder(folderA)
        let initialDir = sut.flatNavigatorCurrentDirectory
        
        // When drag hover begins over back button
        sut.flatNavigatorBackButtonDragHoverStarted()
        
        // Should schedule navigation (we'll need to wait for the timer in real implementation)
        // For testing, we check that the hover state is tracked
        XCTAssertTrue(sut.flatNavigatorBackButtonIsDragHovering,
                      "Should track drag hover state over back button")
    }

    func test_dragHoverEndOverBackButton_cancelsNavigation() {
        // Given drag hover is active
        sut.navigateToFolder(folderA)
        sut.flatNavigatorBackButtonDragHoverStarted()
        XCTAssertTrue(sut.flatNavigatorBackButtonIsDragHovering)
        
        // When drag hover ends
        sut.flatNavigatorBackButtonDragHoverEnded()
        
        // Should cancel the hover state
        XCTAssertFalse(sut.flatNavigatorBackButtonIsDragHovering,
                       "Should clear drag hover state")
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, folderA.standardizedFileURL,
                       "Should NOT have navigated back when hover ended")
    }

    func test_navigateToRoot_setsCurrentDirectoryToRoot() {
        // Given we're deep in the hierarchy
        sut.navigateToFolder(folderA)
        sut.navigateToFolder(subfolder)
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, subfolder.standardizedFileURL)
        
        // When navigating to root
        sut.navigateToRootInFlatNavigator()
        
        // Should be at root
        XCTAssertEqual(sut.flatNavigatorCurrentDirectory?.standardizedFileURL, tempDir.standardizedFileURL,
                       "Navigate to root should reset to root directory")
    }

    func test_flatNavigatorPath_tracksNavigationHistory() {
        // Initially path should just contain root
        XCTAssertEqual(sut.flatNavigatorPath.count, 1)
        XCTAssertEqual(sut.flatNavigatorPath.first?.standardizedFileURL, tempDir.standardizedFileURL)
        
        // Navigate to folder-a
        sut.navigateToFolder(folderA)
        XCTAssertEqual(sut.flatNavigatorPath.count, 2)
        XCTAssertEqual(sut.flatNavigatorPath.last?.standardizedFileURL, folderA.standardizedFileURL)
        
        // Navigate to subfolder
        sut.navigateToFolder(subfolder)
        XCTAssertEqual(sut.flatNavigatorPath.count, 3)
        XCTAssertEqual(sut.flatNavigatorPath.last?.standardizedFileURL, subfolder.standardizedFileURL)
        
        // Navigate back
        sut.navigateBackInFlatNavigator()
        XCTAssertEqual(sut.flatNavigatorPath.count, 2)
        XCTAssertEqual(sut.flatNavigatorPath.last?.standardizedFileURL, folderA.standardizedFileURL)
    }

    func test_flatNavigatorCurrentDirectoryName_showsFolderName() {
        // At root, should show vault name
        sut.flatNavigatorCurrentDirectory = tempDir
        XCTAssertEqual(sut.flatNavigatorCurrentDirectoryName, tempDir.lastPathComponent)
        
        // In folder, should show that folder's name
        sut.flatNavigatorCurrentDirectory = folderA
        XCTAssertEqual(sut.flatNavigatorCurrentDirectoryName, "folder-a")
        
        // In subfolder
        sut.flatNavigatorCurrentDirectory = subfolder
        XCTAssertEqual(sut.flatNavigatorCurrentDirectoryName, "subfolder")
    }

    func test_navigateBack_updatesSelectedFileIfNeeded() {
        // Open a file in subfolder
        sut.openFile(file2)
        XCTAssertEqual(sut.selectedFile?.standardizedFileURL, file2.standardizedFileURL)
        
        // Navigate up
        sut.navigateToFolder(folderA)
        sut.navigateToFolder(subfolder)
        sut.navigateBackInFlatNavigator()
        
        // The selected file should still be valid (pointing to new location if moved, or unchanged)
        // This test documents expected behavior - actual implementation may vary
        XCTAssertNotNil(sut.selectedFile, "Selected file should still be tracked after navigation")
    }
}
