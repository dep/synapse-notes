import XCTest
@testable import Synapse

/// Tests for note-reference normalisation and note-index building.
///
/// `normalizedNoteReference(_:)` and `noteIndex()` are private helpers that underpin
/// every wiki-link lookup in the app — graph construction, backlink resolution, and
/// embed rendering all route through them. Their behaviour is verified here through
/// the public APIs that depend on them:
///
///   • `detectEmbeds(in:)`  — verifies alias / section stripping and whitespace handling
///   • `embedContent(for:)` — verifies case-insensitive file resolution
///   • `vaultGraph(…)`       — verifies duplicate-title deduplication (first path wins)
///   • `relationshipsForSelectedFile()` — verifies full link-resolution pipeline
final class NoteReferenceResolutionTests: XCTestCase {

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
    private func makeFile(named name: String, content: String, in dir: URL? = nil) -> URL {
        let directory = dir ?? tempDir!
        let url = directory.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - normalizedNoteReference via detectEmbeds

    func test_detectEmbeds_plainNoteName_returnedAsIs() {
        let embeds = sut.detectEmbeds(in: "![[My Note]]")
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "My Note")
    }

    func test_detectEmbeds_aliasedLink_stripsAlias() {
        // ![[Note|Display Alias]] → noteName should be "Note Title", not include the alias
        let embeds = sut.detectEmbeds(in: "![[Note Title|Display Alias]]")
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "Note Title",
                       "Alias text after | should be stripped from the embed noteName")
    }

    func test_detectEmbeds_sectionLink_stripsSection() {
        // ![[Note#Introduction]] → noteName should be "My Note", not "My Note#Introduction"
        let embeds = sut.detectEmbeds(in: "![[My Note#Introduction]]")
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "My Note",
                       "Section heading after # should be stripped from the embed noteName")
    }

    func test_detectEmbeds_sectionAndAlias_stripsBoth() {
        // ![[Note#section|alias]] → noteName should be "My Note"
        let embeds = sut.detectEmbeds(in: "![[My Note#Intro|See intro]]")
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "My Note",
                       "Both section heading and alias should be stripped")
    }

    func test_detectEmbeds_leadingAndTrailingWhitespace_stripped() {
        // ![[  Note  ]] → noteName should be trimmed
        let embeds = sut.detectEmbeds(in: "![[  My Note  ]]")
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "My Note",
                       "Leading/trailing whitespace should be stripped from embed noteName")
    }

    func test_detectEmbeds_whitespaceOnlyBrackets_ignored() {
        // ![[   ]] → empty normalised key → should be dropped
        let embeds = sut.detectEmbeds(in: "![[   ]]")
        XCTAssertTrue(embeds.isEmpty,
                      "An embed with only whitespace inside brackets should be ignored")
    }

    func test_detectEmbeds_multipleEmbeds_allParsed() {
        let text = "![[Alpha]] and ![[Beta|alias]] and ![[Gamma#section]]"
        let embeds = sut.detectEmbeds(in: text)
        XCTAssertEqual(embeds.count, 3)
        XCTAssertEqual(embeds[0].noteName, "Alpha")
        XCTAssertEqual(embeds[1].noteName, "Beta")
        XCTAssertEqual(embeds[2].noteName, "Gamma")
    }

    // MARK: - Case-insensitive resolution via embedContent

    func test_embedContent_exactCase_resolvesFile() {
        makeFile(named: "project.md", content: "Project content")
        sut.refreshAllFiles()

        let embed = AppState.EmbedMatch(noteName: "project", range: NSRange(location: 0, length: 0))
        let content = sut.embedContent(for: embed)
        XCTAssertEqual(content, "Project content")
    }

    func test_embedContent_uppercasedReference_resolvesFile() {
        makeFile(named: "my-note.md", content: "Hello from my note")
        sut.refreshAllFiles()

        let embed = AppState.EmbedMatch(noteName: "MY-NOTE", range: NSRange(location: 0, length: 0))
        let content = sut.embedContent(for: embed)
        XCTAssertEqual(content, "Hello from my note",
                       "embedContent should resolve files case-insensitively")
    }

    func test_embedContent_mixedCaseReference_resolvesFile() {
        makeFile(named: "My-Note.md", content: "Mixed case file")
        sut.refreshAllFiles()

        let embed = AppState.EmbedMatch(noteName: "my-note", range: NSRange(location: 0, length: 0))
        let content = sut.embedContent(for: embed)
        XCTAssertEqual(content, "Mixed case file",
                       "Lowercase reference should resolve a mixed-case filename")
    }

    func test_embedContent_nonExistentNote_returnsNil() {
        sut.refreshAllFiles()
        let embed = AppState.EmbedMatch(noteName: "does-not-exist", range: NSRange(location: 0, length: 0))
        XCTAssertNil(sut.embedContent(for: embed),
                     "embedContent should return nil for a note that doesn't exist in the vault")
    }

    func test_embedContent_nestedEmbedsDisabledByDefault_convertsToWikiLinks() {
        // outer.md embeds inner.md; when allowNesting=false, the embed inside outer becomes a plain link
        makeFile(named: "inner.md", content: "Inner content")
        makeFile(named: "outer.md", content: "![[inner]]")
        sut.refreshAllFiles()

        let embed = AppState.EmbedMatch(noteName: "outer", range: NSRange(location: 0, length: 0))
        let content = sut.embedContent(for: embed, allowNesting: false)
        // The ![[inner]] inside outer.md should be demoted to [[inner]]
        XCTAssertEqual(content, "[[inner]]",
                       "Nested embed ![[inner]] should be converted to [[inner]] when allowNesting is false")
    }

    // MARK: - noteIndex deduplication via vaultGraph

    func test_vaultGraph_duplicateTitles_producesOnlyOneNode() throws {
        // Create two subdirectories with identically-named notes
        let dirA = tempDir.appendingPathComponent("aaa-folder", isDirectory: true)
        let dirB = tempDir.appendingPathComponent("zzz-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        makeFile(named: "note.md", content: "Content A", in: dirA)
        makeFile(named: "note.md", content: "Content B", in: dirB)
        makeFile(named: "linker.md", content: "[[note]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: false, includeOrphans: true)
        let noteNodes = graph.nodes.filter { $0.title.lowercased() == "note" }
        XCTAssertEqual(noteNodes.count, 1,
                       "Two files with the same title should produce exactly one graph node")
    }

    func test_vaultGraph_wikiLink_createsDirectedEdge() throws {
        makeFile(named: "source.md", content: "Links to [[target]]")
        makeFile(named: "target.md", content: "Target note")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: false, includeOrphans: true)
        let sourceNode = graph.nodes.first { $0.title == "source" }
        let targetNode = graph.nodes.first { $0.title == "target" }

        XCTAssertNotNil(sourceNode, "Source note should appear as a graph node")
        XCTAssertNotNil(targetNode, "Target note should appear as a graph node")

        let edge = graph.edges.first {
            $0.fromID == sourceNode?.id && $0.toID == targetNode?.id
        }
        XCTAssertNotNil(edge, "A wiki link should create a directed edge in the vault graph")
    }

    func test_vaultGraph_caseInsensitiveLink_resolvesToRealNode_notGhost() {
        makeFile(named: "target.md", content: "Target")
        makeFile(named: "source.md", content: "Links to [[TARGET]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: true, includeOrphans: true)
        let realTargetNode = graph.nodes.first { $0.title == "target" && !$0.isGhost }
        let ghostForTarget = graph.nodes.first {
            $0.isGhost && $0.id.lowercased() == "target"
        }

        XCTAssertNotNil(realTargetNode,
                        "target.md should appear as a real (non-ghost) node in the graph")
        XCTAssertNil(ghostForTarget,
                     "[[TARGET]] should resolve to 'target' case-insensitively, not become a ghost node")
    }

    func test_vaultGraph_aliasLink_resolvesToRealNode() {
        makeFile(named: "target.md", content: "Target")
        makeFile(named: "source.md", content: "[[target|Custom Alias]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: true, includeOrphans: true)
        let realTargetNode = graph.nodes.first { $0.title == "target" && !$0.isGhost }
        XCTAssertNotNil(realTargetNode,
                        "An aliased wiki link [[target|alias]] should resolve to the real node")
    }

    func test_vaultGraph_sectionLink_resolvesToRealNode() {
        makeFile(named: "target.md", content: "Target")
        makeFile(named: "source.md", content: "[[target#Heading]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: true, includeOrphans: true)
        let realTargetNode = graph.nodes.first { $0.title == "target" && !$0.isGhost }
        XCTAssertNotNil(realTargetNode,
                        "A section link [[target#Heading]] should resolve to the real node")
    }

    // MARK: - relationshipsForSelectedFile pipeline

    func test_relationshipsForSelectedFile_outboundLink_resolved() throws {
        makeFile(named: "target.md", content: "Target")
        let source = makeFile(named: "source.md", content: "[[target]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let relationships = sut.relationshipsForSelectedFile()
        XCTAssertNotNil(relationships)
        XCTAssertEqual(relationships?.outbound.count, 1,
                       "Should have exactly one resolved outbound link")
        XCTAssertEqual(relationships?.outbound.first?.lastPathComponent, "target.md",
                       "Outbound link should resolve to target.md")
    }

    func test_relationshipsForSelectedFile_aliasedLink_resolvedCorrectly() throws {
        makeFile(named: "target.md", content: "Target")
        let source = makeFile(named: "source.md", content: "[[target|Custom Alias]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let relationships = sut.relationshipsForSelectedFile()
        XCTAssertNotNil(relationships)
        XCTAssertEqual(relationships?.outbound.count, 1,
                       "Aliased wiki link should count as one resolved outbound link")
        XCTAssertEqual(relationships?.outbound.first?.lastPathComponent, "target.md",
                       "Aliased link should resolve to the correct file")
    }

    func test_relationshipsForSelectedFile_sectionLink_resolvedCorrectly() throws {
        makeFile(named: "target.md", content: "Target")
        let source = makeFile(named: "source.md", content: "[[target#Section]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let relationships = sut.relationshipsForSelectedFile()
        XCTAssertNotNil(relationships)
        XCTAssertEqual(relationships?.outbound.count, 1,
                       "Section link should resolve to one outbound file")
    }

    func test_relationshipsForSelectedFile_unresolvedLink_appearsInUnresolved() {
        let source = makeFile(named: "source.md", content: "[[nonexistent note]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let relationships = sut.relationshipsForSelectedFile()
        XCTAssertNotNil(relationships)
        XCTAssertTrue(relationships?.unresolved.contains("nonexistent note") ?? false,
                      "A link with no matching note should appear in the unresolved array")
        XCTAssertEqual(relationships?.outbound.count, 0,
                       "An unresolved link should not appear in outbound resolved links")
    }
}
