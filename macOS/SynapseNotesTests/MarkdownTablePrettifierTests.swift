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
        let input = "|a|bb|\n|---|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "| a   | bb  |\n| --- | --- |\n")
    }

    func test_prettify_preservesTrailingNewline_whenInputHasOne() {
        let input = "|a|bb|\n|---|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertTrue(result?.formatted.hasSuffix("\n") ?? false)
    }

    func test_prettify_noTrailingNewline_outputHasNoTrailingNewline() {
        let input = "|a|bb|\n|---|---|"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertFalse(result?.formatted.hasSuffix("\n") ?? true)
        XCTAssertEqual(result?.formatted, "| a   | bb  |\n| --- | --- |")
    }

    /// GitHub Actions checks out with LF, but editors on Windows use CRLF; prettify must accept both.
    func test_prettify_normalizesCRLF() {
        let input = "|a|bb|\r\n|---|---|\r\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "| a   | bb  |\n| --- | --- |\n")
    }

    // MARK: - Separator row handling

    func test_prettify_leftAligned_separatorHasNoPrefixOrSuffixColon() {
        let input = "| L | R |\n| --- | --- |\n| a | b |\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "| L   | R   |\n| --- | --- |\n| a   | b   |\n")
    }

    func test_prettify_rightAligned_separatorHasSuffixColon() {
        let input = "| L | R |\n| --- | ---: |\n| a | b |\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "| L   |   R |\n| --- | ---: |\n| a   |   b |\n")
    }

    func test_prettify_centerAligned_separatorHasBothColons() {
        let input = "| L | R |\n| :---: | :---: |\n| a | b |\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "|  L  |  R  |\n| :---: | :---: |\n|  a  |  b  |\n")
    }

    // MARK: - Minimum column width

    func test_prettify_shortContent_columnWidthAtLeast3() {
        let input = "|x|\n|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertEqual(result?.formatted, "| x   |\n| --- |\n")
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
        let input = "|a|bb|\n|---|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 7)

        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.cursorOffset, result!.formatted.count)
    }

    func test_prettify_cursorAtZero_returnsNonNegativeOffset() {
        let input = "|a|bb|\n|---|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.cursorOffset, 0)
    }

    func test_prettify_cursorMapsAcrossPadding() {
        let input = "|a|bb|\n|---|---|\n"
        let afterA = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 3)
        let afterPipe = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 4)

        XCTAssertEqual(afterA?.cursorOffset, 7)
        XCTAssertEqual(afterPipe?.cursorOffset, 8)
    }

    // MARK: - Multi-column alignment mix

    func test_prettify_multipleAlignments_allRowsHaveSameColumnCount() {
        let input = "|x|y|z|\n|:---|:---:|---:|\n|1|2|3|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: input, cursorOffsetInTable: 0)

        let expected = "| x   |  y  |   z |\n| --- | :---: | ---: |\n| 1   |  2  |   3 |\n"
        XCTAssertEqual(result?.formatted, expected)
        let lines = result!.formatted.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        let pipeCounts = lines.map { $0.filter { $0 == "|" }.count }
        XCTAssertEqual(Set(pipeCounts), [4], "Every row should have the same pipe structure (3 columns)")
    }

    // MARK: - PrettifyResult properties

    func test_prettifyResult_formattedIsDifferentFromRawWhenInputIsUnaligned() {
        let raw = "|a|bb|\n|---|---|\n"
        let result = MarkdownTablePrettifier.prettify(tableText: raw, cursorOffsetInTable: 0)

        XCTAssertNotNil(result)
        XCTAssertNotEqual(result!.formatted, raw)
    }
}
