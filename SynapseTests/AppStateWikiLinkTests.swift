import XCTest
@testable import Synapse

/// Tests for wiki-link parsing and backlink (relationship) resolution.
/// This covers the core "notes graph" feature: [[outbound]] links, unresolved
/// references, inbound backlinks, alias/anchor syntax, and case insensitivity.
final class AppStateWikiLinkTests: XCTestCase {

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

    // MARK: - No selected file

    func test_noSelectedFile_returnsNil() {
        XCTAssertNil(sut.relationshipsForSelectedFile())
    }

    // MARK: - Notes with no links

    func test_noteWithNoLinks_emptyRelationships() {
        let note = makeNote(named: "Solo", content: "Just plain text, no links.")
        sut.refreshAllFiles()
        sut.openFile(note)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertTrue(rel.outbound.isEmpty)
        XCTAssertTrue(rel.unresolved.isEmpty)
    }

    // MARK: - Outbound links

    func test_outboundLink_toExistingNote_appearsInOutbound() {
        let a = makeNote(named: "NoteA", content: "See [[NoteB]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.outbound.first?.lastPathComponent, "NoteB.md")
        XCTAssertTrue(rel.unresolved.isEmpty)
    }

    func test_outboundLink_toMissingNote_appearsInUnresolved() {
        let a = makeNote(named: "NoteA", content: "Links to [[Ghost]]")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertTrue(rel.outbound.isEmpty)
        XCTAssertEqual(rel.unresolved.count, 1)
        XCTAssertEqual(rel.unresolved.first, "ghost")
    }

    func test_duplicateOutboundLinks_deduped() {
        let a = makeNote(named: "NoteA", content: "[[NoteB]] and [[NoteB]] again")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
    }

    // MARK: - Inbound links (backlinks)

    func test_inboundLinks_otherNoteReferencesSelected() {
        let a = makeNote(named: "NoteA", content: "Hello World")
        makeNote(named: "NoteB", content: "References [[NoteA]]")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.inbound.count, 1)
        XCTAssertEqual(rel.inbound.first?.lastPathComponent, "NoteB.md")
    }

    func test_noInboundLinks_whenNoOtherNoteReferences() {
        let a = makeNote(named: "Isolated", content: "Nothing here")
        makeNote(named: "Other", content: "No links at all")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertTrue(rel.inbound.isEmpty)
    }

    // MARK: - Case-insensitive matching

    func test_wikiLink_caseInsensitive_matchesNote() {
        makeNote(named: "My Note")
        let b = makeNote(named: "Ref", content: "See [[MY NOTE]]")
        sut.refreshAllFiles()
        sut.openFile(b)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.outbound.first?.deletingPathExtension().lastPathComponent, "My Note")
    }

    // MARK: - Pipe alias syntax  [[Target|Display Text]]

    func test_pipeAlias_resolvesToTarget() {
        let a = makeNote(named: "NoteA", content: "[[NoteB|Click Here]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.outbound.first?.lastPathComponent, "NoteB.md")
    }

    // MARK: - Heading anchor syntax  [[Target#Section]]

    func test_headingAnchor_resolvesToTarget() {
        let a = makeNote(named: "NoteA", content: "[[NoteB#Introduction]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.outbound.first?.lastPathComponent, "NoteB.md")
    }

    // MARK: - Multiple outbound links

    func test_multipleOutboundLinks_allResolved() {
        let a = makeNote(named: "Hub", content: "[[Alpha]], [[Beta]], [[Gamma]]")
        makeNote(named: "Alpha")
        makeNote(named: "Beta")
        makeNote(named: "Gamma")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 3)
        XCTAssertTrue(rel.unresolved.isEmpty)
    }

    func test_mixedResolvedAndUnresolved() {
        let a = makeNote(named: "Mixed", content: "[[Exists]] and [[Missing]]")
        makeNote(named: "Exists")
        sut.refreshAllFiles()
        sut.openFile(a)

        let rel = sut.relationshipsForSelectedFile()!
        XCTAssertEqual(rel.outbound.count, 1)
        XCTAssertEqual(rel.unresolved.count, 1)
    }
}
