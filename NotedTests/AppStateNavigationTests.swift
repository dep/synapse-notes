import XCTest
@testable import Noted

/// Tests for file-navigation history: goBack, goForward, canGoBack, canGoForward,
/// and history truncation when a new file is opened mid-history.
final class AppStateNavigationTests: XCTestCase {

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
        sut.openFolder(tempDir)

        fileA = tempDir.appendingPathComponent("a.md")
        fileB = tempDir.appendingPathComponent("b.md")
        fileC = tempDir.appendingPathComponent("c.md")
        FileManager.default.createFile(atPath: fileA.path, contents: "A".data(using: .utf8))
        FileManager.default.createFile(atPath: fileB.path, contents: "B".data(using: .utf8))
        FileManager.default.createFile(atPath: fileC.path, contents: "C".data(using: .utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_noFiles_cannotNavigate() {
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    // MARK: - canGoBack / canGoForward after opening files

    func test_openOneFile_noNavigation() {
        sut.openFile(fileA)
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    func test_openTwoFiles_canGoBack_notForward() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        XCTAssertTrue(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    func test_openThreeFiles_canGoBack_notForward() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.openFile(fileC)
        XCTAssertTrue(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    // MARK: - goBack

    func test_goBack_navigatesToPreviousFile() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    func test_goBack_updatesCanGoForward() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        XCTAssertTrue(sut.canGoForward)
    }

    func test_goBack_atStart_doesNothing() {
        sut.openFile(fileA)
        sut.goBack()
        XCTAssertEqual(sut.selectedFile, fileA)
        XCTAssertFalse(sut.canGoBack)
    }

    // MARK: - goForward

    func test_goForward_afterGoBack_navigatesToNextFile() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        sut.goForward()
        XCTAssertEqual(sut.selectedFile, fileB)
        XCTAssertFalse(sut.canGoForward)
    }

    func test_goForward_atEnd_doesNothing() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goForward()
        XCTAssertEqual(sut.selectedFile, fileB)
    }

    // MARK: - History truncation

    func test_openFile_afterGoBack_truncatesForwardHistory() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        sut.openFile(fileC)
        XCTAssertFalse(sut.canGoForward)
        XCTAssertEqual(sut.selectedFile, fileC)
    }

    func test_openFile_afterGoBack_allowsBackToA() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.goBack()
        sut.openFile(fileC)
        sut.goBack()
        XCTAssertEqual(sut.selectedFile, fileA)
    }

    // MARK: - Full round-trip navigation

    func test_fullNavigation_ABCBackBackForwardForward() {
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.openFile(fileC)

        sut.goBack()
        XCTAssertEqual(sut.selectedFile, fileB)
        XCTAssertTrue(sut.canGoBack)
        XCTAssertTrue(sut.canGoForward)

        sut.goBack()
        XCTAssertEqual(sut.selectedFile, fileA)
        XCTAssertFalse(sut.canGoBack)
        XCTAssertTrue(sut.canGoForward)

        sut.goForward()
        XCTAssertEqual(sut.selectedFile, fileB)

        sut.goForward()
        XCTAssertEqual(sut.selectedFile, fileC)
        XCTAssertFalse(sut.canGoForward)
    }
}
