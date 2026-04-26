import XCTest
@testable import Synapse

/// Tests for the graph data model structs: NoteGraphNode, NoteGraphEdge, and NoteGraph.
/// These structs are the output of AppState.vaultGraph() / localGraph() and are consumed
/// by Grape for graph rendering.  Their properties drive which nodes are shown, which
/// edges connect them, and which nodes are flagged as ghost (unresolved link targets).
///
/// AppStateGraphTests covers higher-level vaultGraph() / localGraph() behaviour;
/// these tests focus on the structs themselves in isolation.
final class NoteGraphModelTests: XCTestCase {

    // MARK: - NoteGraphNode — real note

    func test_noteGraphNode_realNote_urlIsSet() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let node = NoteGraphNode(id: "note", title: "Note", url: url, isGhost: false)
        XCTAssertEqual(node.url, url)
    }

    func test_noteGraphNode_realNote_isGhostIsFalse() {
        let node = NoteGraphNode(id: "note", title: "Note",
                                 url: URL(fileURLWithPath: "/vault/Note.md"), isGhost: false)
        XCTAssertFalse(node.isGhost)
    }

    func test_noteGraphNode_realNote_titleMatchesInput() {
        let node = NoteGraphNode(id: "meeting-notes", title: "Meeting Notes",
                                 url: URL(fileURLWithPath: "/vault/Meeting Notes.md"), isGhost: false)
        XCTAssertEqual(node.title, "Meeting Notes")
    }

    func test_noteGraphNode_realNote_idMatchesInput() {
        let node = NoteGraphNode(id: "my-note", title: "My Note",
                                 url: URL(fileURLWithPath: "/vault/My Note.md"), isGhost: false)
        XCTAssertEqual(node.id, "my-note")
    }

    // MARK: - NoteGraphNode — ghost node (unresolved wikilink target)

    func test_noteGraphNode_ghostNode_urlIsNil() {
        let node = NoteGraphNode(id: "phantom", title: "phantom", url: nil, isGhost: true)
        XCTAssertNil(node.url)
    }

    func test_noteGraphNode_ghostNode_isGhostIsTrue() {
        let node = NoteGraphNode(id: "phantom", title: "phantom", url: nil, isGhost: true)
        XCTAssertTrue(node.isGhost)
    }

    func test_noteGraphNode_ghostNode_titleIsLinkText() {
        let node = NoteGraphNode(id: "phantom", title: "phantom", url: nil, isGhost: true)
        XCTAssertEqual(node.title, "phantom")
    }

    // MARK: - NoteGraphNode — Identifiable

    func test_noteGraphNode_identifiable_idIsStable() {
        let node = NoteGraphNode(id: "stable-id", title: "Title",
                                 url: URL(fileURLWithPath: "/vault/note.md"), isGhost: false)
        // Identifiable.id is the same as the stored id
        XCTAssertEqual(node.id, "stable-id")
    }

    // MARK: - NoteGraphNode — Equatable

    func test_noteGraphNode_equatable_sameValues_areEqual() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let a = NoteGraphNode(id: "note", title: "Note", url: url, isGhost: false)
        let b = NoteGraphNode(id: "note", title: "Note", url: url, isGhost: false)
        XCTAssertEqual(a, b)
    }

    func test_noteGraphNode_equatable_differentID_areNotEqual() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let a = NoteGraphNode(id: "a", title: "Note", url: url, isGhost: false)
        let b = NoteGraphNode(id: "b", title: "Note", url: url, isGhost: false)
        XCTAssertNotEqual(a, b)
    }

    func test_noteGraphNode_equatable_ghostVsReal_areNotEqual() {
        let a = NoteGraphNode(id: "phantom", title: "phantom", url: nil, isGhost: true)
        let b = NoteGraphNode(id: "phantom", title: "phantom",
                              url: URL(fileURLWithPath: "/vault/phantom.md"), isGhost: false)
        XCTAssertNotEqual(a, b)
    }

    func test_noteGraphNode_equatable_differentTitle_areNotEqual() {
        let url = URL(fileURLWithPath: "/vault/Note.md")
        let a = NoteGraphNode(id: "note", title: "Note A", url: url, isGhost: false)
        let b = NoteGraphNode(id: "note", title: "Note B", url: url, isGhost: false)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - NoteGraphEdge — id format

    func test_noteGraphEdge_id_isFormattedAsFromDashArrowTo() {
        let edge = NoteGraphEdge(id: "alpha->beta", fromID: "alpha", toID: "beta")
        XCTAssertEqual(edge.id, "alpha->beta")
    }

    func test_noteGraphEdge_fromID_matchesInput() {
        let edge = NoteGraphEdge(id: "alpha->beta", fromID: "alpha", toID: "beta")
        XCTAssertEqual(edge.fromID, "alpha")
    }

    func test_noteGraphEdge_toID_matchesInput() {
        let edge = NoteGraphEdge(id: "alpha->beta", fromID: "alpha", toID: "beta")
        XCTAssertEqual(edge.toID, "beta")
    }

    func test_noteGraphEdge_id_uniquePerDirectedPair() {
        let ab = NoteGraphEdge(id: "a->b", fromID: "a", toID: "b")
        let ba = NoteGraphEdge(id: "b->a", fromID: "b", toID: "a")
        XCTAssertNotEqual(ab.id, ba.id, "a->b and b->a are distinct directed edges")
    }

    // MARK: - NoteGraphEdge — Identifiable

    func test_noteGraphEdge_identifiable_idProperty() {
        let edge = NoteGraphEdge(id: "hub->spoke", fromID: "hub", toID: "spoke")
        XCTAssertEqual(edge.id, "hub->spoke")
    }

    // MARK: - NoteGraph — container struct

    func test_noteGraph_emptyNodesAndEdges() {
        let graph = NoteGraph(nodes: [], edges: [])
        XCTAssertTrue(graph.nodes.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func test_noteGraph_storesNodes() {
        let node = NoteGraphNode(id: "n", title: "N",
                                 url: URL(fileURLWithPath: "/vault/n.md"), isGhost: false)
        let graph = NoteGraph(nodes: [node], edges: [])
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.nodes.first, node)
    }

    func test_noteGraph_storesEdges() {
        let edge = NoteGraphEdge(id: "a->b", fromID: "a", toID: "b")
        let graph = NoteGraph(nodes: [], edges: [edge])
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges.first?.id, "a->b")
    }

    func test_noteGraph_multipleNodesAndEdges() {
        let nodeA = NoteGraphNode(id: "a", title: "A",
                                  url: URL(fileURLWithPath: "/vault/A.md"), isGhost: false)
        let nodeB = NoteGraphNode(id: "b", title: "B",
                                  url: URL(fileURLWithPath: "/vault/B.md"), isGhost: false)
        let edge  = NoteGraphEdge(id: "a->b", fromID: "a", toID: "b")

        let graph = NoteGraph(nodes: [nodeA, nodeB], edges: [edge])
        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
    }
}
