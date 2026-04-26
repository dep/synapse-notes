import XCTest
@testable import Synapse

/// Tests for `commandPaletteScoreByFolderName(forURL:needle:)` used when the command palette
/// surfaces folder matches alongside files and tags.
final class CommandPaletteFolderScoringTests: XCTestCase {

    private func folderURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/vault/\(name)")
    }

    func test_emptyNeedle_returnsZero() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("Projects"), needle: ""),
            0
        )
    }

    func test_noMatch_returnsZero() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("Notes"), needle: "xyz"),
            0
        )
    }

    func test_exactFolderNameMatch_yields200() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("Archive"), needle: "Archive"),
            200
        )
    }

    func test_exactMatch_isCaseInsensitive() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("PROJECTS"), needle: "projects"),
            200
        )
    }

    func test_prefixMatch_yields100() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("Projects-2024"), needle: "Projects"),
            100
        )
    }

    func test_substringMatch_yields60() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(forURL: folderURL("my-archive-box"), needle: "archive"),
            60
        )
    }

    func test_parentPathDoesNotAffectScore() {
        let shallow = commandPaletteScoreByFolderName(
            forURL: folderURL("Work"),
            needle: "Work"
        )
        let deep = commandPaletteScoreByFolderName(
            forURL: URL(fileURLWithPath: "/vault/a/b/c/Work"),
            needle: "Work"
        )
        XCTAssertEqual(shallow, deep)
    }

    func test_pathSubstringDoesNotMatch() {
        XCTAssertEqual(
            commandPaletteScoreByFolderName(
                forURL: URL(fileURLWithPath: "/vault/Work/notes"),
                needle: "Work"
            ),
            0,
            "Only the folder name (last path component) participates in scoring"
        )
    }

    func test_exactRanksHigherThanPrefix() {
        let exact = commandPaletteScoreByFolderName(forURL: folderURL("dev"), needle: "dev")
        let prefix = commandPaletteScoreByFolderName(forURL: folderURL("dev-tools"), needle: "dev")
        XCTAssertGreaterThan(exact, prefix)
    }

    func test_prefixRanksHigherThanSubstring() {
        let prefix = commandPaletteScoreByFolderName(forURL: folderURL("docs-old"), needle: "docs")
        let substring = commandPaletteScoreByFolderName(forURL: folderURL("my-docs-extra"), needle: "docs")
        XCTAssertGreaterThan(prefix, substring)
    }
}
