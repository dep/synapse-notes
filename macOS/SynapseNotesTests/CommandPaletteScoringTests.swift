import XCTest
@testable import Synapse

/// Tests for `commandPaletteScoreByFilename(forURL:needle:)`.
///
/// The scoring algorithm ranks files by filename only:
///
///   • Exact stem match           → 200
///   • Exact filename match       → 190
///   • Prefix match on stem       → 100
///   • Prefix match on filename   → 90
///   • Substring match on stem    → 60
///   • Substring match on filename→ 45
///
/// Path-based matching has been removed - files are only matched by filename.
final class CommandPaletteScoringTests: XCTestCase {

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/vault/\(name)")
    }

    // MARK: - Zero / no match

    func test_noMatch_returnsZero() {
        let score = commandPaletteScoreByFilename(
            forURL: url("readme.md"),
            needle: "xyz"
        )
        XCTAssertEqual(score, 0, "Non-matching needle must yield zero")
    }

    func test_emptyNeedle_returnsZero() {
        let score = commandPaletteScoreByFilename(
            forURL: url("readme.md"),
            needle: ""
        )
        XCTAssertEqual(score, 0, "Empty needle must yield zero")
    }

    // MARK: - Exact stem match (200)

    func test_exactStemMatch_yields200() {
        let score = commandPaletteScoreByFilename(
            forURL: url("readme.md"),
            needle: "readme"
        )
        XCTAssertEqual(score, 200, "Exact stem match must yield 200")
    }

    func test_exactStemMatch_caseInsensitive() {
        let score = commandPaletteScoreByFilename(
            forURL: url("README.md"),
            needle: "readme"
        )
        XCTAssertEqual(score, 200, "Exact stem match should be case-insensitive")
    }

    // MARK: - Exact filename match (190)

    func test_exactFilenameMatch_yields190() {
        let score = commandPaletteScoreByFilename(
            forURL: url("notes.txt"),
            needle: "notes.txt"
        )
        XCTAssertEqual(score, 190, "Exact filename match must yield 190")
    }

    // MARK: - Prefix matches

    func test_stemPrefixMatch_yields100() {
        let score = commandPaletteScoreByFilename(
            forURL: url("readme-extended.md"),
            needle: "readme"
        )
        XCTAssertEqual(score, 100, "Stem prefix match must yield 100")
    }

    func test_filenamePrefixMatch_yields90() {
        // filename "notes-v2.txt" prefix with full extension included → 90
        let score = commandPaletteScoreByFilename(
            forURL: url("notes-v2.txt"),
            needle: "notes-v2.t"
        )
        XCTAssertEqual(score, 90, "Filename prefix match (with extension) must yield 90")
    }

    // MARK: - Substring matches

    func test_stemSubstringMatch_yields60() {
        let score = commandPaletteScoreByFilename(
            forURL: url("my-readme-file.md"),
            needle: "readme"
        )
        XCTAssertEqual(score, 60, "Stem substring match must yield 60")
    }

    func test_filenameSubstringMatch_yields45() {
        // needle matches filename (with extension) but not just the stem
        let score = commandPaletteScoreByFilename(
            forURL: url("note.backup"),
            needle: "backup"
        )
        // stem = "note", filename = "note.backup"
        // "backup" not in stem, but "backup" in filename → 45
        XCTAssertEqual(score, 45, "Filename substring match must yield 45")
    }

    // MARK: - Ordering contracts

    func test_exactMatch_ranksHigherThanPrefixMatch() {
        let exact = commandPaletteScoreByFilename(
            forURL: url("notes.md"),
            needle: "notes"
        )
        let prefix = commandPaletteScoreByFilename(
            forURL: url("notes-2024.md"),
            needle: "notes"
        )
        XCTAssertGreaterThan(exact, prefix, "Exact match must outrank a prefix match")
    }

    func test_prefixMatch_ranksHigherThanSubstringMatch() {
        let prefix = commandPaletteScoreByFilename(
            forURL: url("readme-extended.md"),
            needle: "readme"
        )
        let substring = commandPaletteScoreByFilename(
            forURL: url("my-readme-file.md"),
            needle: "readme"
        )
        XCTAssertGreaterThan(prefix, substring, "Prefix match must outrank a substring match")
    }

    // MARK: - Path-based matching removed

    func test_pathDoesNotAffectScore() {
        // Files with same name in different paths should have same score
        let shallow = commandPaletteScoreByFilename(
            forURL: url("readme.md"),
            needle: "readme"
        )
        let deep = commandPaletteScoreByFilename(
            forURL: URL(fileURLWithPath: "/vault/a/b/c/readme.md"),
            needle: "readme"
        )
        XCTAssertEqual(shallow, deep,
                       "Path should not affect filename-only scoring")
    }

    func test_pathSubstringDoesNotMatch() {
        // Searching for "folder" should NOT match files inside "folder/"
        let score = commandPaletteScoreByFilename(
            forURL: URL(fileURLWithPath: "/vault/folder/note.md"),
            needle: "folder"
        )
        XCTAssertEqual(score, 0, "Path substrings should not match in filename-only search")
    }
}
