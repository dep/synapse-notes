import XCTest
@testable import Synapse

/// Tests for portable folder customization keys (`FolderAppearance`, `FolderColor`, `FolderIcon`).
/// Wrong IDs or Codable drift breaks settings round-trips and sidebar rendering.
final class FolderAppearanceModelTests: XCTestCase {

    // MARK: - FolderColor.palette

    func test_folderColor_palette_hasExpectedCount() {
        XCTAssertEqual(FolderColor.palette.count, 12)
    }

    func test_folderColor_colorFor_knownId_returnsMatch() {
        XCTAssertEqual(FolderColor.color(for: "rose")?.id, "rose")
        XCTAssertEqual(FolderColor.color(for: "sand")?.label, "Sand")
    }

    func test_folderColor_colorFor_unknownId_returnsNil() {
        XCTAssertNil(FolderColor.color(for: "not-a-color"))
    }

    func test_folderColor_palette_idsAreUnique() {
        let ids = FolderColor.palette.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - FolderIcon.set

    func test_folderIcon_set_containsExpectedSymbols() {
        XCTAssertEqual(FolderIcon.icon(for: "star")?.symbolName, "star")
        XCTAssertEqual(FolderIcon.icon(for: "book")?.symbolName, "book.closed")
        XCTAssertEqual(FolderIcon.icon(for: "robot")?.symbolName, "cpu")
    }

    func test_folderIcon_iconFor_unknownId_returnsNil() {
        XCTAssertNil(FolderIcon.icon(for: "no-such-icon"))
    }

    func test_folderIcon_set_idsAreUnique() {
        let ids = FolderIcon.set.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - FolderAppearance

    func test_folderAppearance_id_isRelativePath() {
        let sut = FolderAppearance(relativePath: "Projects/Work", colorKey: nil, iconKey: nil)
        XCTAssertEqual(sut.id, "Projects/Work")
    }

    func test_folderAppearance_resolvedColor_nilWhenNoKey() {
        let sut = FolderAppearance(relativePath: "a", colorKey: nil, iconKey: nil)
        XCTAssertNil(sut.resolvedColor)
    }

    func test_folderAppearance_resolvedColor_validKey() {
        let sut = FolderAppearance(relativePath: "a", colorKey: "rose", iconKey: nil)
        XCTAssertNotNil(sut.resolvedColor)
    }

    func test_folderAppearance_resolvedSymbolName_validKey() {
        let sut = FolderAppearance(relativePath: "a", colorKey: nil, iconKey: "moon")
        XCTAssertEqual(sut.resolvedSymbolName, "moon")
    }

    func test_folderAppearance_roundTripsCodable() throws {
        let original = FolderAppearance(relativePath: "Notes/Daily", colorKey: "mint", iconKey: "calendar")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FolderAppearance.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
