import XCTest
import Combine
@testable import Synapse

/// Tests for Issue #143: async file scanning with generation counter.
/// Verifies that rebuildFileLists dispatches to a background queue,
/// the generation counter discards stale scans, and allFiles is always
/// assigned on the main thread.
final class AsyncFileScanTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(named name: String, content: String = "x") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Scan completes and populates allFiles

    func test_refreshAllFiles_populatesAllFiles_afterScanCompletes() {
        makeFile(named: "alpha.md")
        makeFile(named: "beta.md")

        // Subscribe before triggering the scan so we don't miss the emission.
        let expectation = XCTestExpectation(description: "allFiles populated")
        sut.$allFiles
            .first(where: { !$0.isEmpty })
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.openFolder(tempDir)

        wait(for: [expectation], timeout: 3.0)

        XCTAssertEqual(sut.allFiles.count, 2)
        let names = Set(sut.allFiles.map { $0.lastPathComponent })
        XCTAssertTrue(names.contains("alpha.md"))
        XCTAssertTrue(names.contains("beta.md"))
    }

    // MARK: - allFiles assignment happens on main thread

    func test_refreshAllFiles_assignsAllFilesOnMainThread() {
        makeFile(named: "note.md")

        let expectation = XCTestExpectation(description: "allFiles assigned on main thread")
        sut.$allFiles
            .first(where: { !$0.isEmpty })
            .sink { [weak self] _ in
                XCTAssertTrue(Thread.isMainThread,
                              "allFiles must be assigned on the main thread")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.rootURL = tempDir
        sut.refreshAllFiles()

        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - Stale generation is discarded

    /// When a second scan starts before the first one finishes, only the
    /// latest scan's results should be applied to allFiles.
    func test_staleScanGeneration_isDiscarded_whenNewerScanCompletes() {
        // Create a file that will appear in both scans
        makeFile(named: "file.md")

        // Subscribe before the first scan
        let firstScanExpectation = XCTestExpectation(description: "first scan completes")
        sut.$allFiles
            .first(where: { !$0.isEmpty })
            .sink { _ in firstScanExpectation.fulfill() }
            .store(in: &cancellables)

        sut.openFolder(tempDir)
        wait(for: [firstScanExpectation], timeout: 3.0)
        XCTAssertFalse(sut.allFiles.isEmpty, "precondition: first scan should populate allFiles")

        // Now trigger two rapid refreshes, add a new file between them
        makeFile(named: "extra.md")

        let secondScanExpectation = XCTestExpectation(description: "second batch scans complete")
        sut.$allFiles
            .first(where: { $0.contains(where: { $0.lastPathComponent == "extra.md" }) })
            .sink { _ in secondScanExpectation.fulfill() }
            .store(in: &cancellables)

        sut.refreshAllFiles()
        sut.refreshAllFiles()

        wait(for: [secondScanExpectation], timeout: 3.0)

        // Both files should be present after the latest scan completes
        let names = Set(sut.allFiles.map { $0.lastPathComponent })
        XCTAssertTrue(names.contains("file.md"))
        XCTAssertTrue(names.contains("extra.md"))
    }

    // MARK: - Empty vault produces empty lists

    func test_refreshAllFiles_emptyVault_producesEmptyFileLists() {
        // Empty vault: openFolder sets rootURL and runs a scan
        sut.openFolder(tempDir)

        XCTAssertTrue(sut.allFiles.isEmpty,
                      "Empty vault should produce no allFiles entries")
        XCTAssertTrue(sut.allProjectFiles.isEmpty,
                      "Empty vault should produce no allProjectFiles entries")
    }

    // MARK: - rootURL nil clears lists immediately

    func test_refreshAllFiles_withNilRootURL_clearsFileListsImmediately() {
        makeFile(named: "note.md")

        // Subscribe before the first scan
        let populatedExpectation = XCTestExpectation(description: "files populated first")
        sut.$allFiles
            .first(where: { !$0.isEmpty })
            .sink { _ in populatedExpectation.fulfill() }
            .store(in: &cancellables)

        sut.openFolder(tempDir)
        wait(for: [populatedExpectation], timeout: 3.0)
        XCTAssertFalse(sut.allFiles.isEmpty, "precondition: files should be populated")

        sut.rootURL = nil
        sut.refreshAllFiles()

        XCTAssertTrue(sut.allFiles.isEmpty,
                      "allFiles should be cleared immediately when rootURL is nil")
    }
}
