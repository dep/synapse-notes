import XCTest
@testable import Synapse

/// Tests for MarkdownTablePrettifier — the engine that re-formats raw
/// Markdown pipe-tables into aligned columns and adjusts the cursor offset.
///
/// This is critical functionality: every Tab keypress inside a table goes
/// through this code. A regression here silently corrupts table content or
/// drops the cursor to a wrong position.
final class MarkdownTablePrettifierTests: XCTestCase {

    // MARK: - Basic prettification

    func test_prettify_simpleTable_producesEquallyPaddedColumns() {
        let input = "| A | B |\n| --- | --- |\n| Short | Much longer |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result, "A valid two-column table must produce a result")
        let lines = result!.formatted.components(separatedBy: "\n").filter { !$0.isEmpty }
        let widths = Set(lines.map { $0.count })
        XCTAssertEqual(widths.count, 1, "All rows should have equal width after prettification — got widths: \(widths)")
    }

    func test_prettify_preservesTrailingNewline_whenInputHasOne() {
        let input = "| Col |\n| --- |\n| val |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.formatted.hasSuffix("\n"), "Trailing newline in input must be preserved in output")
    }

    func test_prettify_noTrailingNewline_outputHasNoTrailingNewline() {
        let input = "| Col |\n| --- |\n| val |"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.formatted.hasSuffix("\n"), "No trailing newline in input → no trailing newline in output")
    }

    /// GitHub Actions checks out with LF, but editors on Windows use CRLF; prettify must accept both.
    func test_prettify_normalizesCRLF() {
        let text = "|a|bb|\r\n|---|---|\r\n|x|y|\r\n"

        let result = MarkdownTablePrettifier.prettify(tableText: text, cursorOffsetInTable: 0)

        XCTAssertNotNil(result, "Expected prettify to succeed with CRLF line endings")
        XCTAssertTrue(result!.formatted.hasSuffix("\n"))
        XCTAssertTrue(result!.formatted.contains("| a  | bb |"))
        XCTAssertTrue(result!.formatted.contains("| --- | --- |"))
        XCTAssertTrue(result!.formatted.contains("| x  | y  |"))
    }

    // MARK: - Separator row handling

    func test_prettify_leftAligned_separatorHasNoPrefixOrSuffixColon() {
        let input = "| Name |\n| --- |\n| Alice |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        let separatorLine = result!.formatted.components(separatedBy: "\n")[1]
        XCTAssertFalse(separatorLine.contains(":"), "Left-aligned separator must not contain colons — got: \(separatorLine)")
    }

    func test_prettify_rightAligned_separatorHasSuffixColon() {
        let input = "| Num |\n| ---: |\n| 42 |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        let separatorLine = result!.formatted.components(separatedBy: "\n")[1]
        XCTAssertTrue(separatorLine.contains(":"), "Right-aligned separator must end with a colon — got: \(separatorLine)")
        XCTAssertFalse(separatorLine.contains(":---"), "Right-aligned separator must not start with ':' — got: \(separatorLine)")
    }

    func test_prettify_centerAligned_separatorHasBothColons() {
        let input = "| Mid |\n| :---: |\n| 42 |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        let separatorLine = result!.formatted.components(separatedBy: "\n")[1]
        XCTAssertTrue(separatorLine.contains(":---"), "Center-aligned separator must start with ':' — got: \(separatorLine)")
        XCTAssertTrue(separatorLine.hasSuffix(": |") || separatorLine.contains(":"), "Center-aligned separator must end with ':' — got: \(separatorLine)")
    }

    // MARK: - Minimum column width

    func test_prettify_shortContent_columnWidthAtLeast3() {
        let input = "| X |\n| - |\n| Y |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        let separatorLine = result!.formatted.components(separatedBy: "\n")[1]
        let dashCount = separatorLine.filter { $0 == "-" }.count
        XCTAssertGreaterThanOrEqual(dashCount, 3, "Separator must contain at least 3 dashes — got: \(separatorLine)")
    }

    // MARK: - Guard / nil cases

    func test_prettify_onlyOneRow_returnsNil() {
        let input = "| Col |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNil(result, "A table with only a header row (no separator) must not be prettified")
    }

    func test_prettify_missingSeparatorRow_returnsNil() {
        let input = "| Col |\n| NotASeparator |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNil(result, "A table without a valid separator row must not be prettified")
    }

    func test_prettify_emptyString_returnsNil() {
        let result = MarkdownTablePrettifier.prettify(tableText: "", cursorOffsetInTable: 0)

        XCTAssertNil(result, "Prettifying an empty string must return nil")
    }

    // MARK: - Cell parsing

    func test_parseCells_leadingAndTrailingPipes_stripsExactlyOne() {
        let cells = MarkdownTablePrettifier.parseCells(from: "| Alpha | Beta |")

        XCTAssertEqual(cells.count, 2, "Should parse 2 cells from a 2-column row — got: \(cells)")
        XCTAssertEqual(cells[0].trimmingCharacters(in: .whitespaces), "Alpha")
        XCTAssertEqual(cells[1].trimmingCharacters(in: .whitespaces), "Beta")
    }

    func test_parseCells_noPipes_returnsSingleCell() {
        let cells = MarkdownTablePrettifier.parseCells(from: "NoPipes")

        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0], "NoPipes")
    }

    func test_parseCells_emptyString_returnsSingleEmptyString() {
        let cells = MarkdownTablePrettifier.parseCells(from: "")

        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0], "")
    }

    // MARK: - Cursor adjustment

    func test_prettify_cursorAtColumnBoundary_staysWithinFormattedLength() {
        let input = "| A | B |\n| --- | --- |\n| val | longerVal |\n"
        let cursor = (input as NSString).length - 2

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: cursor)

        XCTAssertNotNil(result)
        let formattedLen = (result!.formatted as NSString).length
        XCTAssertLessThanOrEqual(result!.cursorOffset, formattedLen,
                                 "Adjusted cursor must not exceed the formatted text length")
        XCTAssertGreaterThanOrEqual(result!.cursorOffset, 0,
                                    "Adjusted cursor must be non-negative")
    }

    func test_prettify_cursorAtZero_returnsNonNegativeOffset() {
        let input = "| H |\n| --- |\n| R |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.cursorOffset, 0, "Cursor at 0 must stay non-negative after adjustment")
    }

    // MARK: - Multi-column alignment mix

    func test_prettify_multipleAlignments_allRowsHaveSameColumnCount() {
        let input = "| L | C | R |\n| :--- | :---: | ---: |\n| a | b | c |\n| longer | x | y |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        let lines = result!.formatted.components(separatedBy: "\n").filter { !$0.isEmpty }
        let pipeCounts = lines.map { $0.filter { $0 == "|" }.count }
        XCTAssertEqual(Set(pipeCounts).count, 1,
                       "All rows must have the same number of pipes (same column count) — got: \(pipeCounts)")
    }

    // MARK: - PrettifyResult properties

    func test_prettifyResult_formattedIsDifferentFromRawWhenInputIsUnaligned() {
        let input = "| Short | A very long header |\n| --- | --- |\n| x | y |\n"

        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertNotEqual(result!.formatted, input,
                          "Prettifier should pad unaligned columns, producing different output")
    }
}
