import XCTest
@testable import Synapse

/// Tests for AppState.vaultGraph() — the full-vault graph data model
/// used by the Global Graph and Local Graph views.
final class AppStateGraphTests: XCTestCase {

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

    // MARK: - Empty vault

    func test_vaultGraph_emptyVault_returnsEmptyGraph() {
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertTrue(graph.nodes.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    // MARK: - Nodes

    func test_vaultGraph_singleNote_producesOneNode_whenOrphansIncluded() {
        makeNote(named: "Alpha", content: "Hello world")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeOrphans: true)

        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.nodes.first?.title, "Alpha")
    }

    func test_vaultGraph_orphanNote_excludedByDefault() {
        makeNote(named: "Orphan", content: "No links here")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertTrue(graph.nodes.isEmpty)
    }

    func test_vaultGraph_multipleNotes_producesOneNodePerNote_whenOrphansIncluded() {
        makeNote(named: "A")
        makeNote(named: "B")
        makeNote(named: "C")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeOrphans: true)

        XCTAssertEqual(graph.nodes.count, 3)
        let titles = graph.nodes.map(\.title).sorted()
        XCTAssertEqual(titles, ["A", "B", "C"])
    }

    func test_vaultGraph_nodeURL_matchesFileURL() {
        let urlA = makeNote(named: "NoteA", content: "[[NoteB]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        let nodeA = graph.nodes.first { $0.title == "NoteA" }
        XCTAssertEqual(nodeA?.url, urlA)
    }

    func test_vaultGraph_ghostNodes_includedWhenRequested() {
        makeNote(named: "NoteA", content: "See [[Ghost]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: true)

        // NoteA (real) + Ghost (ghost)
        XCTAssertEqual(graph.nodes.count, 2)
        let ghostNode = graph.nodes.first { $0.isGhost }
        XCTAssertNotNil(ghostNode)
        XCTAssertEqual(ghostNode?.title, "ghost")
        XCTAssertNil(ghostNode?.url)
    }

    func test_vaultGraph_ghostNodes_excludedByDefault() {
        makeNote(named: "NoteA", content: "See [[Ghost]]")
        sut.refreshAllFiles()

        // includeOrphans: true so NoteA stays; we're testing ghost exclusion specifically
        let graph = sut.vaultGraph(includeOrphans: true)

        // Only NoteA — unresolved ghost is excluded by default
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertFalse(graph.nodes.contains { $0.isGhost })
    }

    func test_vaultGraph_realNodesAreNotGhosts() {
        makeNote(named: "NoteA", content: "[[NoteB]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertTrue(graph.nodes.allSatisfy { !$0.isGhost })
    }

    // MARK: - Edges

    func test_vaultGraph_noLinks_producesNoEdges() {
        makeNote(named: "Solo")
        sut.refreshAllFiles()

        // includeOrphans: true so the note exists; we're testing edge count specifically
        let graph = sut.vaultGraph(includeOrphans: true)

        XCTAssertTrue(graph.edges.isEmpty)
    }

    func test_vaultGraph_resolvedLink_producesOneEdge() {
        makeNote(named: "NoteA", content: "See [[NoteB]]")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertEqual(graph.edges.count, 1)
        let edge = graph.edges.first!
        let fromNode = graph.nodes.first { $0.id == edge.fromID }!
        let toNode = graph.nodes.first { $0.id == edge.toID }!
        XCTAssertEqual(fromNode.title, "NoteA")
        XCTAssertEqual(toNode.title, "NoteB")
    }

    func test_vaultGraph_unresolvedLink_producesEdgeToGhostNode_whenGhostsIncluded() {
        makeNote(named: "NoteA", content: "See [[Phantom]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph(includeGhosts: true)

        XCTAssertEqual(graph.edges.count, 1)
        let toID = graph.edges.first!.toID
        let ghostNode = graph.nodes.first { $0.id == toID }!
        XCTAssertTrue(ghostNode.isGhost)
    }

    func test_vaultGraph_unresolvedLink_producesNoEdge_byDefault() {
        makeNote(named: "NoteA", content: "See [[Phantom]]")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertTrue(graph.edges.isEmpty)
    }

    func test_vaultGraph_duplicateLinks_deduped() {
        makeNote(named: "NoteA", content: "[[NoteB]] and [[NoteB]] again")
        makeNote(named: "NoteB")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertEqual(graph.edges.count, 1)
    }

    func test_vaultGraph_multipleLinks_producesMultipleEdges() {
        makeNote(named: "Hub", content: "[[Alpha]] [[Beta]] [[Gamma]]")
        makeNote(named: "Alpha")
        makeNote(named: "Beta")
        makeNote(named: "Gamma")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        XCTAssertEqual(graph.edges.count, 3)
    }

    // MARK: - Node connection count

    func test_vaultGraph_nodeConnectionCount_reflectsInboundAndOutbound() {
        makeNote(named: "Hub", content: "[[Spoke1]] [[Spoke2]]")
        makeNote(named: "Spoke1", content: "[[Hub]]")
        makeNote(named: "Spoke2")
        sut.refreshAllFiles()

        let graph = sut.vaultGraph()

        let hub = graph.nodes.first { $0.title == "Hub" }!
        // Hub has 2 outbound edges + 1 inbound edge = 3 connections
        let hubEdges = graph.edges.filter { $0.fromID == hub.id || $0.toID == hub.id }
        XCTAssertEqual(hubEdges.count, 3)
    }

    // MARK: - Local subgraph

    func test_localGraph_returnsOnlySelectedNoteAndNeighbors() {
        let hub = makeNote(named: "Hub", content: "[[Spoke1]] [[Spoke2]]")
        makeNote(named: "Spoke1")
        makeNote(named: "Spoke2")
        makeNote(named: "Unrelated")
        sut.refreshAllFiles()
        sut.openFile(hub)

        let local = sut.localGraph()

        XCTAssertNotNil(local)
        // Hub + Spoke1 + Spoke2 = 3 nodes (Unrelated excluded)
        XCTAssertEqual(local!.nodes.count, 3)
        let titles = local!.nodes.map(\.title).sorted()
        XCTAssertEqual(titles, ["Hub", "Spoke1", "Spoke2"])
    }

    func test_localGraph_noSelectedFile_returnsNil() {
        makeNote(named: "NoteA")
        sut.refreshAllFiles()

        XCTAssertNil(sut.localGraph())
    }

    func test_localGraph_includesInboundNeighbors() {
        let target = makeNote(named: "Target")
        makeNote(named: "Linker", content: "[[Target]]")
        sut.refreshAllFiles()
        sut.openFile(target)

        let local = sut.localGraph()!

        let titles = local.nodes.map(\.title).sorted()
        XCTAssertTrue(titles.contains("Linker"))
    }
}
