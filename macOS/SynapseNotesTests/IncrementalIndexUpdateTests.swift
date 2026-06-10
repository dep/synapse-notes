import XCTest
@testable import Synapse

/// Tests for Issue #260: FSEvents batches that only touch existing, already-indexed
/// notes are serviced by an incremental re-parse instead of a full vault rescan.
/// Structural changes (creations, deletions, unknown paths) still trigger the full
/// scan, and an in-flight index pass forces the fallback so generation counters
/// arbitrate as before.
final class IncrementalIndexUpdateTests: XCTestCase {

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

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String) -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Pure content modification takes the incremental path

    func test_modifyingExistingNote_updatesIndexesWithoutFullRescan() {
        let note = makeNote(named: "Alpha", content: "#projecta [[Beta]] aardvark")
        makeNote(named: "Beta", content: "plain")
        sut.openFolder(tempDir)
        XCTAssertEqual(sut.cachedTagCounts["projecta"], 1, "precondition: initial index built")

        let scansBefore = sut.fullScanCount

        try! "#projectb [[Gamma]] zebra".write(to: note, atomically: true, encoding: .utf8)
        sut.processVaultEvents(paths: [note.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore,
                       "a pure content modification must not trigger a full vault scan")
        // Tags reflect the change
        XCTAssertNil(sut.cachedTagCounts["projecta"])
        XCTAssertEqual(sut.cachedTagCounts["projectb"], 1)
        // Backlinks reflect the change
        XCTAssertNil(sut.cachedBacklinks["beta"])
        XCTAssertEqual(sut.cachedBacklinks["gamma"], [note])
        // Word search index reflects the change
        XCTAssertNil(sut.wordSearchIndex["aardvark"])
        XCTAssertEqual(sut.wordSearchIndex["zebra"], [note])
        XCTAssertTrue(sut.candidateFiles(for: "zebra").contains(note))
    }

    func test_modifyingExistingNote_viaPrivateVarEventPath_isHandledIncrementally() {
        // FSEvents reports resolved real paths: /var/folders/… arrives as /private/var/….
        let note = makeNote(named: "Symlinked", content: "#old")
        sut.openFolder(tempDir)
        let scansBefore = sut.fullScanCount

        try! "#new".write(to: note, atomically: true, encoding: .utf8)
        let eventPath = note.path.hasPrefix("/private/") ? note.path : "/private" + note.path
        sut.processVaultEvents(paths: [eventPath])

        XCTAssertEqual(sut.fullScanCount, scansBefore,
                       "the /private-prefixed event path should map to the cached note")
        XCTAssertNil(sut.cachedTagCounts["old"])
        XCTAssertEqual(sut.cachedTagCounts["new"], 1)
    }

    // MARK: - Structural changes fall back to the full rescan

    func test_creatingNote_triggersFullRescanAndIndexesIt() {
        makeNote(named: "Alpha", content: "alpha")
        sut.openFolder(tempDir)
        let scansBefore = sut.fullScanCount

        let newNote = makeNote(named: "Fresh", content: "#brandnew quokka")
        sut.processVaultEvents(paths: [newNote.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore + 1,
                       "an unknown path must fall back to a full rescan")
        XCTAssertTrue(sut.allFiles.contains(newNote))
        XCTAssertEqual(sut.cachedTagCounts["brandnew"], 1)
        XCTAssertEqual(sut.wordSearchIndex["quokka"], [newNote])
    }

    func test_deletingNote_triggersFullRescanAndRemovesIt() {
        let doomed = makeNote(named: "Doomed", content: "#gone unicorns")
        makeNote(named: "Stays", content: "stay")
        sut.openFolder(tempDir)
        XCTAssertEqual(sut.cachedTagCounts["gone"], 1, "precondition: initial index built")
        let scansBefore = sut.fullScanCount

        try! FileManager.default.removeItem(at: doomed)
        sut.processVaultEvents(paths: [doomed.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore + 1,
                       "a deletion must fall back to a full rescan")
        XCTAssertFalse(sut.allFiles.contains(doomed))
        XCTAssertNil(sut.cachedTagCounts["gone"])
        XCTAssertNil(sut.wordSearchIndex["unicorns"])
    }

    func test_mixedBatch_withUnknownPath_triggersFullRescan() {
        let note = makeNote(named: "Known", content: "#known")
        sut.openFolder(tempDir)
        let scansBefore = sut.fullScanCount

        try! "#known still".write(to: note, atomically: true, encoding: .utf8)
        let newNote = makeNote(named: "Surprise", content: "surprise")
        sut.processVaultEvents(paths: [note.path, newNote.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore + 1,
                       "one unknown path in the batch must force the full rescan")
        XCTAssertTrue(sut.allFiles.contains(newNote))
    }

    func test_gitignoreEventPath_triggersFullRescan() {
        makeNote(named: "Alpha", content: "alpha")
        sut.openFolder(tempDir)
        let scansBefore = sut.fullScanCount

        let gitignore = tempDir.appendingPathComponent(".gitignore")
        try! "build/\n".write(to: gitignore, atomically: true, encoding: .utf8)
        sut.processVaultEvents(paths: [gitignore.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore + 1,
                       "touching ignore rules must re-run the full scan (and git ls-files)")
    }

    // MARK: - Generation safety: in-flight index pass forces the fallback

    func test_incrementalPath_skippedWhileIndexingInFlight() {
        let note = makeNote(named: "Alpha", content: "#alpha")
        sut.openFolder(tempDir)
        let scansBefore = sut.fullScanCount

        sut.isIndexing = true
        try! "#changed".write(to: note, atomically: true, encoding: .utf8)
        sut.processVaultEvents(paths: [note.path])

        XCTAssertEqual(sut.fullScanCount, scansBefore + 1,
                       "while a full index pass is in flight, events must take the full-rescan path")
        XCTAssertEqual(sut.cachedTagCounts["changed"], 1,
                       "the fallback rescan must still index the new content")
    }
}
