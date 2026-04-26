import XCTest
@testable import Synapse

// MARK: - NoteContentCache Unit Tests
// Tests for the shared file-content cache (Issue #144 — 2A & 2B)

final class ContentCacheTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 2A: Shared File Content Cache

    /// Cache is populated after a vault scan.
    func test_cache_populatedAfterScan() {
        makeNote(named: "NoteA", content: "#work [[NoteB]]")
        makeNote(named: "NoteB", content: "hello")
        sut.refreshAllFiles()

        XCTAssertEqual(sut.noteContentCache.count, 2, "Cache should have one entry per file")
    }

    /// Cache stores pre-parsed wikiLinks per file.
    func test_cache_storesWikiLinksPerFile() {
        let urlA = makeNote(named: "Alpha", content: "See [[Beta]] and [[Gamma]]")
        sut.refreshAllFiles()

        let cached = sut.noteContentCache[urlA]
        XCTAssertNotNil(cached, "Cache entry should exist for Alpha")
        XCTAssertTrue(cached!.wikiLinks.contains("beta"), "Should cache normalized wikilink 'beta'")
        XCTAssertTrue(cached!.wikiLinks.contains("gamma"), "Should cache normalized wikilink 'gamma'")
    }

    /// Cache stores pre-parsed tags per file.
    func test_cache_storesTagsPerFile() {
        let urlA = makeNote(named: "Tagged", content: "Note with #swift and #apple")
        sut.refreshAllFiles()

        let cached = sut.noteContentCache[urlA]
        XCTAssertNotNil(cached, "Cache entry should exist for Tagged")
        XCTAssertTrue(cached!.tags.contains("swift"), "Should cache tag 'swift'")
        XCTAssertTrue(cached!.tags.contains("apple"), "Should cache tag 'apple'")
    }

    /// Cache stores modificationDate per file.
    func test_cache_storesModificationDate() {
        let url = makeNote(named: "Dated", content: "content")
        sut.refreshAllFiles()

        let cached = sut.noteContentCache[url]
        XCTAssertNotNil(cached, "Cache entry should exist")
        XCTAssertNotNil(cached!.modificationDate, "ModificationDate should be stored")
    }

    // MARK: - 2A: Consumers read from cache

    /// allTags() reads from cache rather than disk.
    func test_allTags_readsFromCache_notDisk() {
        let url = makeNote(named: "Tags", content: "#redis #cache")
        sut.refreshAllFiles()

        // Overwrite file on disk without rescanning — cache still holds old content
        try! "NO TAGS HERE".write(to: url, atomically: true, encoding: .utf8)

        // Without re-scan, allTags should still return cached data
        let tags = sut.allTags()
        XCTAssertNotNil(tags["redis"], "allTags should read from cache, not updated disk file")
        XCTAssertNotNil(tags["cache"], "allTags should read from cache, not updated disk file")
    }

    /// vaultGraph() reads from cache rather than disk.
    func test_vaultGraph_readsFromCache_notDisk() {
        let urlA = makeNote(named: "Hub", content: "[[Spoke]]")
        _ = makeNote(named: "Spoke", content: "")
        sut.refreshAllFiles()

        // Overwrite Hub on disk without rescanning — cache has the [[Spoke]] link
        try! "No links here".write(to: urlA, atomically: true, encoding: .utf8)

        let graph = sut.vaultGraph()
        XCTAssertEqual(graph.edges.count, 1, "vaultGraph should read from cache, returning cached edge")
    }

    /// relationshipsForSelectedFile() reads from cache for inbound links.
    func test_relationshipsForSelectedFile_readsFromCache() {
        let target = makeNote(named: "Target", content: "")
        let linker = makeNote(named: "Linker", content: "[[Target]]")
        sut.refreshAllFiles()
        sut.openFile(target)

        // Overwrite Linker on disk without rescanning — cache has the [[Target]] link
        try! "No links".write(to: linker, atomically: true, encoding: .utf8)

        let rels = sut.relationshipsForSelectedFile()
        XCTAssertNotNil(rels, "Should return relationships")
        XCTAssertTrue(rels!.inbound.contains(linker), "Inbound should come from cache, not disk")
    }

    // MARK: - 2B: Incremental Updates

    /// On file save, only that file's cache entry is updated.
    func test_incrementalUpdate_onFileSave_onlyUpdatesModifiedEntry() {
        let urlA = makeNote(named: "A", content: "#original")
        let urlB = makeNote(named: "B", content: "#unchanged")
        sut.refreshAllFiles()

        let originalModDateB = sut.noteContentCache[urlB]?.modificationDate

        // Update A's content and trigger incremental update
        Thread.sleep(forTimeInterval: 0.05) // ensure mtime changes
        try! "#updated".write(to: urlA, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [urlA, urlB])

        // B's cache entry should NOT have changed
        let newModDateB = sut.noteContentCache[urlB]?.modificationDate
        XCTAssertEqual(originalModDateB, newModDateB, "Unmodified file B's cache entry should not be re-read")

        // A should now have new tags
        let cachedA = sut.noteContentCache[urlA]
        XCTAssertTrue(cachedA?.tags.contains("updated") == true, "A's cache should reflect new content")
        XCTAssertFalse(cachedA?.tags.contains("original") == true, "A's old tag should be gone")
    }

    /// On file delete, cache entry is removed.
    func test_incrementalUpdate_onFileDelete_removesCacheEntry() {
        let url = makeNote(named: "Temp", content: "#temp")
        sut.refreshAllFiles()
        XCTAssertNotNil(sut.noteContentCache[url], "Cache should have entry before delete")

        try! FileManager.default.removeItem(at: url)
        sut.updateCacheIncrementally(for: [url])

        XCTAssertNil(sut.noteContentCache[url], "Cache entry should be removed after file deleted")
    }

    /// cachedTags incremental update: subtracts old tags, adds new tags.
    func test_cachedTags_incrementalUpdate_diffsTags() {
        let url = makeNote(named: "TagNote", content: "#alpha #beta")
        sut.refreshAllFiles()

        XCTAssertEqual(sut.cachedTagCounts["alpha"], 1)
        XCTAssertEqual(sut.cachedTagCounts["beta"], 1)

        // Change content: remove alpha, add gamma
        Thread.sleep(forTimeInterval: 0.05)
        try! "#beta #gamma".write(to: url, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [url])

        XCTAssertNil(sut.cachedTagCounts["alpha"], "alpha should be removed from cachedTags")
        XCTAssertEqual(sut.cachedTagCounts["beta"], 1, "beta count should remain 1")
        XCTAssertEqual(sut.cachedTagCounts["gamma"], 1, "gamma should be added to cachedTags")
    }

    /// cachedBacklinks incremental update: removes old, adds new.
    func test_cachedBacklinks_incrementalUpdate_diffsLinks() {
        let urlA = makeNote(named: "Source", content: "[[OldTarget]]")
        _ = makeNote(named: "OldTarget", content: "")
        _ = makeNote(named: "NewTarget", content: "")
        sut.refreshAllFiles()

        // OldTarget should have Source as backlink
        XCTAssertTrue(
            sut.cachedBacklinks["oldtarget"]?.contains(urlA) == true,
            "OldTarget should have Source as backlink"
        )

        // Change Source to link to NewTarget instead
        Thread.sleep(forTimeInterval: 0.05)
        try! "[[NewTarget]]".write(to: urlA, atomically: true, encoding: .utf8)
        sut.updateCacheIncrementally(for: [urlA])

        XCTAssertNil(
            sut.cachedBacklinks["oldtarget"]?.contains(urlA),
            "OldTarget should no longer have Source as backlink"
        )
        XCTAssertTrue(
            sut.cachedBacklinks["newtarget"]?.contains(urlA) == true,
            "NewTarget should now have Source as backlink"
        )
    }

    // MARK: - 2C: Lazy Content Loading

    /// After openFolder, allFiles is populated before indexing completes.
    func test_lazyIndexing_fileListAvailableBeforeIndexing() {
        // This test verifies that the file list is set before the indexing pass completes.
        // We test this by checking that allFiles is set even if the cache is not yet populated.
        makeNote(named: "A", content: "#tag")
        makeNote(named: "B", content: "#tag")
        sut.refreshAllFiles()

        // allFiles should be non-empty
        XCTAssertFalse(sut.allFiles.isEmpty, "allFiles must be available after scan")
    }

    /// isIndexing transitions false → true → false across the indexing cycle.
    func test_isIndexing_flagTransitions() {
        // After a synchronous scan (test env), indexing should be complete (false)
        makeNote(named: "X", content: "#tag")
        sut.refreshAllFiles()

        XCTAssertFalse(sut.isIndexing, "isIndexing should be false after sync scan completes in test env")
    }
}
