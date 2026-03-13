import XCTest
@testable import Synapse

/// Tests for AppState.pendingSearchQuery — set when opening a file from all-files search
/// so the editor can highlight the search term after loading.
final class AppStatePendingSearchQueryTests: XCTestCase {

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

    func test_pendingSearchQuery_initiallyNil() {
        XCTAssertNil(sut.pendingSearchQuery)
    }

    // MARK: - Setting

    func test_pendingSearchQuery_canBeSet() {
        sut.pendingSearchQuery = "hello"
        XCTAssertEqual(sut.pendingSearchQuery, "hello")
    }

    func test_pendingSearchQuery_canBeCleared() {
        sut.pendingSearchQuery = "hello"
        sut.pendingSearchQuery = nil
        XCTAssertNil(sut.pendingSearchQuery)
    }

    func test_pendingSearchQuery_canBeSetToEmptyString() {
        sut.pendingSearchQuery = ""
        XCTAssertEqual(sut.pendingSearchQuery, "")
    }

    // MARK: - Consume pattern (mirrors what EditorView does)

    func test_pendingSearchQuery_consumePattern_returnsValueAndClears() {
        sut.pendingSearchQuery = "wikilink"

        // Simulate consumePendingSearchQuery
        let consumed = sut.pendingSearchQuery
        sut.pendingSearchQuery = nil

        XCTAssertEqual(consumed, "wikilink")
        XCTAssertNil(sut.pendingSearchQuery)
    }

    func test_pendingSearchQuery_consumePattern_nilWhenNotSet() {
        let consumed = sut.pendingSearchQuery
        sut.pendingSearchQuery = nil

        XCTAssertNil(consumed)
        XCTAssertNil(sut.pendingSearchQuery)
    }

    func test_pendingSearchQuery_consumeCalledTwice_secondReturnsNil() {
        sut.pendingSearchQuery = "atlas"

        let first = sut.pendingSearchQuery
        sut.pendingSearchQuery = nil
        let second = sut.pendingSearchQuery

        XCTAssertEqual(first, "atlas")
        XCTAssertNil(second)
    }

    // MARK: - Observable

    func test_pendingSearchQuery_set_triggersObjectWillChange() {
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { _ in changeCount += 1 }
        sut.pendingSearchQuery = "test"
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    func test_pendingSearchQuery_clear_triggersObjectWillChange() {
        sut.pendingSearchQuery = "test"
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { _ in changeCount += 1 }
        sut.pendingSearchQuery = nil
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        FileManager.default.createFile(atPath: url.path, contents: content.data(using: .utf8))
        return url
    }
}
