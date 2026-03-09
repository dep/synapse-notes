import XCTest
@testable import Noted

/// Tests for AppState search feature: presentSearch, dismissSearch, and related state.
final class AppStateSearchTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_searchIsHidden() {
        XCTAssertFalse(sut.isSearchPresented)
        XCTAssertEqual(sut.searchMode, .currentFile)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.searchMatchIndex, 0)
        XCTAssertEqual(sut.searchMatchCount, 0)
    }

    // MARK: - presentSearch(.currentFile)

    func test_presentSearch_currentFile_withoutSelectedFile_doesNotPresent() {
        sut.openFolder(tempDir)
        sut.presentSearch(mode: .currentFile)
        XCTAssertFalse(sut.isSearchPresented)
    }

    func test_presentSearch_currentFile_withSelectedFile_presents() {
        let url = makeNote(named: "note")
        sut.openFolder(tempDir)
        sut.openFile(url)
        sut.presentSearch(mode: .currentFile)
        XCTAssertTrue(sut.isSearchPresented)
        XCTAssertEqual(sut.searchMode, .currentFile)
    }

    func test_presentSearch_currentFile_withoutWorkspace_doesNotPresent() {
        // No folder opened, no selected file
        sut.presentSearch(mode: .currentFile)
        XCTAssertFalse(sut.isSearchPresented)
    }

    // MARK: - presentSearch(.allFiles)

    func test_presentSearch_allFiles_withoutSelectedFile_presents() {
        sut.presentSearch(mode: .allFiles)
        XCTAssertTrue(sut.isSearchPresented)
        XCTAssertEqual(sut.searchMode, .allFiles)
    }

    func test_presentSearch_allFiles_withSelectedFile_presents() {
        let url = makeNote(named: "note")
        sut.openFolder(tempDir)
        sut.openFile(url)
        sut.presentSearch(mode: .allFiles)
        XCTAssertTrue(sut.isSearchPresented)
        XCTAssertEqual(sut.searchMode, .allFiles)
    }

    // MARK: - dismissSearch

    func test_dismissSearch_hidesSearch() {
        let url = makeNote(named: "note")
        sut.openFolder(tempDir)
        sut.openFile(url)
        sut.presentSearch(mode: .currentFile)
        XCTAssertTrue(sut.isSearchPresented)

        sut.dismissSearch()
        XCTAssertFalse(sut.isSearchPresented)
    }

    func test_dismissSearch_whenNotPresented_remainsFalse() {
        sut.dismissSearch()
        XCTAssertFalse(sut.isSearchPresented)
    }

    // MARK: - Mode switching

    func test_presentSearch_switchesMode() {
        let url = makeNote(named: "note")
        sut.openFolder(tempDir)
        sut.openFile(url)

        sut.presentSearch(mode: .currentFile)
        XCTAssertEqual(sut.searchMode, .currentFile)

        sut.presentSearch(mode: .allFiles)
        XCTAssertEqual(sut.searchMode, .allFiles)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String) -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }
}
