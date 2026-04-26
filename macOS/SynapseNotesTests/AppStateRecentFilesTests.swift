import XCTest
@testable import Synapse

/// Tests for recentFiles management: deduplication, ordering, and 40-item cap.
final class AppStateRecentFilesTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
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

    private func makeFile(named name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "content".data(using: .utf8))
        return url
    }

    // MARK: - openFile recentFiles

    func test_openFile_prependsToRecentFiles() {
        let fileA = makeFile(named: "a.md")
        sut.openFile(fileA)
        XCTAssertEqual(sut.recentFiles.first, fileA)
    }

    func test_openFile_multipleTimes_mostRecentFirst() {
        let fileA = makeFile(named: "a.md")
        let fileB = makeFile(named: "b.md")
        sut.openFile(fileA)
        sut.openFile(fileB)
        XCTAssertEqual(sut.recentFiles.first, fileB)
        XCTAssertEqual(sut.recentFiles[1], fileA)
    }

    func test_openFile_sameFileTwice_movesToFrontWithoutDuplicate() {
        let fileA = makeFile(named: "a.md")
        let fileB = makeFile(named: "b.md")
        sut.openFile(fileA)
        sut.openFile(fileB)
        sut.openFile(fileA)
        XCTAssertEqual(sut.recentFiles.first, fileA)
        XCTAssertEqual(sut.recentFiles.count, 2, "No duplicate should be added")
    }

    func test_openFile_cap40Entries() {
        var files: [URL] = []
        for i in 0..<41 {
            let f = makeFile(named: "note\(i).md")
            files.append(f)
        }
        for f in files {
            sut.openFile(f)
        }
        XCTAssertEqual(sut.recentFiles.count, 40, "recentFiles should be capped at 40 entries")
        XCTAssertEqual(sut.recentFiles.first, files.last, "Most recently opened file should be first")
    }

    // MARK: - openFileInNewTab recentFiles

    func test_openFileInNewTab_prependsToRecentFiles() {
        let fileA = makeFile(named: "a.md")
        sut.openFileInNewTab(fileA)
        XCTAssertEqual(sut.recentFiles.first, fileA)
    }

    func test_openFileInNewTab_sameFileTwice_noDuplicateInRecentFiles() {
        // When openFileInNewTab is called with an already-open file it switches to the
        // existing tab without re-adding to recentFiles (switchTab does not update recency).
        let fileA = makeFile(named: "a.md")
        let fileB = makeFile(named: "b.md")
        sut.openFileInNewTab(fileA)   // recentFiles: [A]
        sut.openFileInNewTab(fileB)   // recentFiles: [B, A]
        sut.openFileInNewTab(fileA)   // switches to existing tab; no recentFiles change
        XCTAssertEqual(sut.recentFiles.count, 2, "No duplicate should be added when switching to existing tab")
        XCTAssertTrue(sut.recentFiles.contains(fileA), "fileA should still be in recentFiles")
        XCTAssertTrue(sut.recentFiles.contains(fileB), "fileB should still be in recentFiles")
    }

    func test_openFileInNewTab_cap40Entries() {
        for i in 0..<41 {
            let f = makeFile(named: "tab\(i).md")
            sut.openFileInNewTab(f)
        }
        XCTAssertEqual(sut.recentFiles.count, 40, "recentFiles should be capped at 40 entries")
    }

    // MARK: - Mixed openFile / openFileInNewTab

    func test_mixedOpen_openFile_alwaysMovesFileToFront() {
        // openFile always updates recentFiles, even when it replaces the current tab.
        let fileA = makeFile(named: "a.md")
        let fileB = makeFile(named: "b.md")
        let fileC = makeFile(named: "c.md")
        sut.openFile(fileA)           // recentFiles: [A]
        sut.openFileInNewTab(fileB)   // recentFiles: [B, A]
        sut.openFileInNewTab(fileC)   // recentFiles: [C, B, A]
        // openFile moves fileA to front (deduplicates and inserts at 0)
        sut.openFile(fileA)           // recentFiles: [A, C, B]
        XCTAssertEqual(sut.recentFiles, [fileA, fileC, fileB])
    }
}
