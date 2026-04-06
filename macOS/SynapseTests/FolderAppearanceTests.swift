import XCTest
import SwiftUI
@testable import Synapse

/// Tests folder color/icon palette lookups and per-folder appearance (portable vault settings).
final class FolderAppearanceTests: XCTestCase {

    // MARK: - FolderColor

    func test_folderColor_palette_hasTwelveEntries() {
        XCTAssertEqual(FolderColor.palette.count, 12)
    }

    func test_folderColor_colorForKnownId_returnsMatch() {
        let rose = FolderColor.color(for: "rose")
        XCTAssertNotNil(rose)
        XCTAssertEqual(rose?.id, "rose")
        XCTAssertEqual(rose?.label, "Rose")
    }

    func test_folderColor_colorForUnknownId_returnsNil() {
        XCTAssertNil(FolderColor.color(for: "not-a-key"))
    }

    func test_folderColor_paletteIds_areUnique() {
        let ids = FolderColor.palette.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - FolderIcon

    func test_folderIcon_set_isNonEmpty() {
        XCTAssertFalse(FolderIcon.set.isEmpty)
    }

    func test_folderIcon_iconForKnownId_returnsSymbolName() {
        let book = FolderIcon.icon(for: "book")
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.symbolName, "book.closed")
    }

    func test_folderIcon_iconForUnknownId_returnsNil() {
        XCTAssertNil(FolderIcon.icon(for: "missing-icon"))
    }

    func test_folderIcon_setIds_areUnique() {
        let ids = FolderIcon.set.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - FolderAppearance

    func test_folderAppearance_resolvedColor_nilWhenNoKey() {
        let a = FolderAppearance(relativePath: "Notes", colorKey: nil, iconKey: nil)
        XCTAssertNil(a.resolvedColor)
    }

    func test_folderAppearance_resolvedColor_whenKeySet_returnsPaletteColor() {
        let a = FolderAppearance(relativePath: "Work", colorKey: "teal", iconKey: nil)
        XCTAssertNotNil(a.resolvedColor)
        XCTAssertNotNil(FolderColor.color(for: "teal"))
    }

    func test_folderAppearance_resolvedSymbolName_nilWhenNoIconKey() {
        let a = FolderAppearance(relativePath: "x", colorKey: nil, iconKey: nil)
        XCTAssertNil(a.resolvedSymbolName)
    }

    func test_folderAppearance_resolvedSymbolName_matchesSet() {
        let a = FolderAppearance(relativePath: "x", colorKey: nil, iconKey: "moon")
        XCTAssertEqual(a.resolvedSymbolName, "moon")
    }

    func test_folderAppearance_id_isRelativePath() {
        let a = FolderAppearance(relativePath: "A/B", colorKey: "rose", iconKey: "star")
        XCTAssertEqual(a.id, "A/B")
    }

    func test_folderAppearance_roundTripJSON() throws {
        let original = FolderAppearance(relativePath: "Projects/Client", colorKey: "sage", iconKey: "bolt")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FolderAppearance.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
