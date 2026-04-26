import XCTest
@testable import Synapse

/// Additional tests for AppState.relationshipsForSelectedFile() covering scenarios
/// not in AppStateWikiLinkTests:
///   - Multiple inbound backlinks
///   - Self-referential links excluded from inbound
///   - Multiple unresolved ghost links
///   - Duplicate ghost links deduplicated
///   - Bidirectional (hub↔spoke) relationships
///   - Inbound vs. outbound counts when same note links back
final class AppStateRelatedLinksTests: XCTestCase {

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

    // MARK: - Multiple inbound backlinks

    func test_inboundLinks_multipleNotesBothReferenceSelected() {
        let target = makeNote(named: "Hub")
        makeNote(named: "NoteA", content: "See [[Hub]]")
        makeNote(named: "NoteB", content: "Also see [[Hub]]")
        makeNote(named: "NoteC", content: "And see [[Hub]]")
        sut.refreshAllFiles()
        sut.openFile(target)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.inbound.count, 3,
            "All three notes that link to Hub should appear in inbound links")
        let names = rel.inbound.map { $0.deletingPathExtension().lastPathComponent }.sorted()
        XCTAssertEqual(names, ["NoteA", "NoteB", "NoteC"])
    }

    // MARK: - Self-referential links

    func test_selfReferentialLink_isNotCountedAsInbound() {
        // A note that links to itself should appear in outbound but NOT in inbound
        let selfNote = makeNote(named: "SelfRef", content: "This note links to [[SelfRef]]")
        sut.refreshAllFiles()
        sut.openFile(selfNote)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertTrue(rel.inbound.isEmpty,
            "A self-referential link must not appear in the note's own inbound list")
        XCTAssertEqual(rel.outbound.count, 1,
            "The self-link should still appear as an outbound link")
    }

    // MARK: - Multiple unresolved (ghost) links

    func test_unresolvedLinks_twoDistinctGhosts() {
        let note = makeNote(named: "Notes", content: "[[Ghost1]] and [[Ghost2]] are missing")
        sut.refreshAllFiles()
        sut.openFile(note)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.unresolved.count, 2)
        XCTAssertTrue(rel.unresolved.contains("ghost1"))
        XCTAssertTrue(rel.unresolved.contains("ghost2"))
    }

    func test_unresolvedLinks_duplicateGhostsDeduplicated() {
        let note = makeNote(named: "Notes", content: "[[Ghost]] appears twice: [[Ghost]]")
        sut.refreshAllFiles()
        sut.openFile(note)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.unresolved.count, 1,
            "Duplicate unresolved wikilinks to the same ghost target should be deduplicated")
    }

    func test_unresolvedLinks_normalizedToLowercase() {
        let note = makeNote(named: "Notes", content: "[[MISSING]] is unresolved")
        sut.refreshAllFiles()
        sut.openFile(note)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.unresolved.count, 1)
        XCTAssertEqual(rel.unresolved.first, "missing",
            "Unresolved link names should be lowercased")
    }

    // MARK: - Bidirectional relationships (hub ↔ spoke)

    func test_bidirectionalLink_bothOutboundAndInbound() {
        let hub   = makeNote(named: "Hub",   content: "Links to [[Spoke]]")
        let spoke = makeNote(named: "Spoke", content: "Links back to [[Hub]]")
        sut.refreshAllFiles()
        sut.openFile(hub)

        let rel = sut.relationshipsForSelectedFile()!
        // Hub → Spoke (outbound from Hub's perspective)
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.outbound.first?.deletingPathExtension().lastPathComponent, "Spoke")
        // Spoke → Hub (inbound from Hub's perspective)
        XCTAssertEqual(rel.inbound.count, 1)
        XCTAssertEqual(rel.inbound.first?.deletingPathExtension().lastPathComponent, "Spoke")
        XCTAssertTrue(rel.unresolved.isEmpty)
    }

    // MARK: - Mixed resolved, unresolved, and inbound

    func test_noteWithResolvedUnresolvedAndInbound() {
        let center = makeNote(named: "Center", content: "[[Exists]] and [[Missing]]")
        makeNote(named: "Exists")
        makeNote(named: "Linker", content: "Points to [[Center]]")
        sut.refreshAllFiles()
        sut.openFile(center)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1,
            "One resolved outbound link to Exists")
        XCTAssertEqual(rel.unresolved.count, 1,
            "One unresolved link to Missing")
        XCTAssertEqual(rel.inbound.count, 1,
            "One inbound backlink from Linker")
    }

    // MARK: - Outbound-only, no inbound

    func test_noteWithOnlyOutboundLinks_hasNoInbound() {
        let source = makeNote(named: "Source", content: "[[Target]]")
        makeNote(named: "Target")
        sut.refreshAllFiles()
        sut.openFile(source)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertTrue(rel.inbound.isEmpty,
            "Source links to Target but nothing links back to Source")
    }

    // MARK: - Inbound-only, no outbound

    func test_noteWithOnlyInboundLinks_hasNoOutbound() {
        let target = makeNote(named: "Target")
        makeNote(named: "A", content: "[[Target]]")
        makeNote(named: "B", content: "[[Target]]")
        sut.refreshAllFiles()
        sut.openFile(target)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertTrue(rel.outbound.isEmpty,
            "Target has no outbound wikilinks in its content")
        XCTAssertEqual(rel.inbound.count, 2,
            "Two notes link to Target")
        XCTAssertTrue(rel.unresolved.isEmpty)
    }
}
