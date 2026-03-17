import XCTest
@testable import Synapse

/// Tests for SidebarPane enum: title strings, raw values, and Identifiable/CaseIterable
/// conformances.  Only the .graph case was previously exercised (in SettingsManagerTests).
/// The other four titles drive the sidebar navigation labels — an incorrect string
/// would show the wrong label without a compile-time error.
final class SidebarPaneTitleTests: XCTestCase {

    // MARK: - title property (all 5 cases)

    func test_files_titleIsFiles() {
        XCTAssertEqual(SidebarPane.files.title, "Files")
    }

    func test_tags_titleIsTags() {
        XCTAssertEqual(SidebarPane.tags.title, "Tags")
    }

    func test_links_titleIsRelated() {
        XCTAssertEqual(SidebarPane.links.title, "Related")
    }

    func test_terminal_titleIsTerminal() {
        XCTAssertEqual(SidebarPane.terminal.title, "Terminal")
    }

    func test_graph_titleIsGraph() {
        XCTAssertEqual(SidebarPane.graph.title, "Graph")
    }

    // MARK: - rawValue (all 5 cases)

    func test_files_rawValueIsFiles() {
        XCTAssertEqual(SidebarPane.files.rawValue, "files")
    }

    func test_tags_rawValueIsTags() {
        XCTAssertEqual(SidebarPane.tags.rawValue, "tags")
    }

    func test_links_rawValueIsLinks() {
        XCTAssertEqual(SidebarPane.links.rawValue, "links")
    }

    func test_terminal_rawValueIsTerminal() {
        XCTAssertEqual(SidebarPane.terminal.rawValue, "terminal")
    }

    func test_graph_rawValueIsGraph() {
        XCTAssertEqual(SidebarPane.graph.rawValue, "graph")
    }

    // MARK: - id == rawValue (Identifiable conformance)

    func test_id_equalsRawValue_forAllCases() {
        for pane in SidebarPane.allCases {
            XCTAssertEqual(pane.id, pane.rawValue,
                "id should equal rawValue for \(pane)")
        }
    }

    // MARK: - CaseIterable — exactly 5 known cases

    func test_allCases_containsExactlyFiveCases() {
        XCTAssertEqual(SidebarPane.allCases.count, 5)
    }

    func test_allCases_containsAllExpectedValues() {
        let expected: [SidebarPane] = [.files, .tags, .links, .terminal, .graph]
        for pane in expected {
            XCTAssertTrue(SidebarPane.allCases.contains(pane),
                "allCases should contain .\(pane.rawValue)")
        }
    }

    // MARK: - Codable round-trip (raw-value based encoding)

    func test_encodeAndDecodeFilesPane() throws {
        let encoded = try JSONEncoder().encode(SidebarPane.files)
        let decoded = try JSONDecoder().decode(SidebarPane.self, from: encoded)
        XCTAssertEqual(decoded, .files)
    }

    func test_encodeAndDecodeLinksPane() throws {
        let encoded = try JSONEncoder().encode(SidebarPane.links)
        let decoded = try JSONDecoder().decode(SidebarPane.self, from: encoded)
        XCTAssertEqual(decoded, .links)
    }

    func test_encodeAndDecodeAllPanes_roundTrip() throws {
        for pane in SidebarPane.allCases {
            let encoded = try JSONEncoder().encode(pane)
            let decoded = try JSONDecoder().decode(SidebarPane.self, from: encoded)
            XCTAssertEqual(decoded, pane,
                "Codable round-trip should preserve .\(pane.rawValue)")
        }
    }

    // MARK: - Raw-value initialisation

    func test_rawValueInit_filesString_returnsFilesPane() {
        XCTAssertEqual(SidebarPane(rawValue: "files"), .files)
    }

    func test_rawValueInit_tagsString_returnsTagsPane() {
        XCTAssertEqual(SidebarPane(rawValue: "tags"), .tags)
    }

    func test_rawValueInit_linksString_returnsLinksPane() {
        XCTAssertEqual(SidebarPane(rawValue: "links"), .links)
    }

    func test_rawValueInit_terminalString_returnsTerminalPane() {
        XCTAssertEqual(SidebarPane(rawValue: "terminal"), .terminal)
    }

    func test_rawValueInit_unknownString_returnsNil() {
        XCTAssertNil(SidebarPane(rawValue: "unknown"))
    }

    // MARK: - Title uniqueness

    func test_allTitlesAreUnique() {
        let titles = SidebarPane.allCases.map(\.title)
        let uniqueTitles = Set(titles)
        XCTAssertEqual(titles.count, uniqueTitles.count,
            "Each SidebarPane should have a unique title string")
    }

    func test_allRawValuesAreUnique() {
        let rawValues = SidebarPane.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        XCTAssertEqual(rawValues.count, unique.count,
            "Each SidebarPane should have a unique rawValue")
    }
}
