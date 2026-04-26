import XCTest
@testable import Synapse

/// Tests for SidebarPaneItem Codable conformance — specifically the `.note` encode path
/// which was previously untested — and SidebarNotePane.title.
///
/// If the encoder emits the wrong type key (e.g. "builtIn" instead of "note"), or omits
/// required fields, the pane silently disappears on the next app restart. These tests
/// catch that regression.
final class SidebarPaneItemCodableTests: XCTestCase {

    // MARK: - SidebarNotePane.title

    func test_sidebarNotePane_title_stripsMarkdownExtension() {
        let pane = SidebarNotePane(path: "/vault/my-note.md")
        XCTAssertEqual(pane.title, "my-note")
    }

    func test_sidebarNotePane_title_stripsTxtExtension() {
        let pane = SidebarNotePane(path: "/vault/readme.txt")
        XCTAssertEqual(pane.title, "readme")
    }

    func test_sidebarNotePane_title_noExtension_returnsFullFilename() {
        let pane = SidebarNotePane(path: "/vault/Makefile")
        XCTAssertEqual(pane.title, "Makefile")
    }

    func test_sidebarNotePane_title_nestedPath_usesLastComponent() {
        let pane = SidebarNotePane(path: "/vault/projects/sprints/sprint-1.md")
        XCTAssertEqual(pane.title, "sprint-1")
    }

    // MARK: - SidebarPaneItem.note: JSON encode structure

    func test_notePaneItem_encodes_withTypeNoteKey() throws {
        let notePane = SidebarNotePane(id: UUID(), path: "/vault/note.md")
        let item = SidebarPaneItem.note(notePane)

        let data = try JSONEncoder().encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "note",
                       "Encoded note pane item should have type == \"note\"")
        XCTAssertNotNil(json?["id"],
                        "Encoded note pane item should carry an 'id' field")
        XCTAssertNotNil(json?["path"],
                        "Encoded note pane item should carry a 'path' field")
    }

    func test_builtInPaneItem_encodesAsPlainString() throws {
        let item = SidebarPaneItem.builtIn(.files)

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(String.self, from: data)

        XCTAssertEqual(decoded, "files",
                       "builtIn pane item should encode as its raw string value, not a keyed object")
    }

    // MARK: - SidebarPaneItem.note: Codable round-trip

    func test_notePaneItem_codableRoundTrip_preservesPathAndID() throws {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let notePane = SidebarNotePane(id: id, path: "/vault/daily.md")
        let item = SidebarPaneItem.note(notePane)

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(SidebarPaneItem.self, from: data)

        XCTAssertEqual(decoded, item,
                       "note pane item should survive a JSON encode → decode round-trip")
    }

    func test_notePaneItem_codableRoundTrip_preservesTitle() throws {
        let notePane = SidebarNotePane(id: UUID(), path: "/vault/reference.md")
        let item = SidebarPaneItem.note(notePane)

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(SidebarPaneItem.self, from: data)

        XCTAssertEqual(decoded.title, "reference",
                       "title derived from the decoded note pane should match the original")
    }

    // MARK: - Mixed array round-trip

    func test_mixedPaneArray_codableRoundTrip() throws {
        let id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let items: [SidebarPaneItem] = [
            .builtIn(.files),
            .note(SidebarNotePane(id: id, path: "/vault/reference.md")),
            .builtIn(.tags),
        ]

        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([SidebarPaneItem].self, from: data)

        XCTAssertEqual(decoded, items,
                       "A mixed array of built-in and note panes should survive a round-trip")
    }

    // MARK: - SidebarPaneItem.id

    func test_notePaneItem_id_hasPrefixNote() {
        let id = UUID()
        let item = SidebarPaneItem.note(SidebarNotePane(id: id, path: "/vault/x.md"))
        XCTAssertEqual(item.id, "note:\(id.uuidString)",
                       "The id of a note pane item should be 'note:<UUID>'")
    }

    func test_builtInPaneItem_id_isRawValue() {
        let item = SidebarPaneItem.builtIn(.tags)
        XCTAssertEqual(item.id, "tags",
                       "The id of a builtIn pane item should be the SidebarPane rawValue")
    }

    // MARK: - SidebarNotePane helpers

    func test_sidebarNotePane_fileURL_matchesGivenPath() {
        let path = "/vault/my-note.md"
        let pane = SidebarNotePane(id: UUID(), path: path)
        XCTAssertEqual(pane.fileURL, URL(fileURLWithPath: path).standardizedFileURL)
    }

    func test_sidebarNotePane_initWithFileURL_matchesDirectPath() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        let id = UUID()
        let pane = SidebarNotePane(id: id, fileURL: url)
        XCTAssertEqual(pane.fileURL, url.standardizedFileURL)
        XCTAssertEqual(pane.id, id)
    }
}
