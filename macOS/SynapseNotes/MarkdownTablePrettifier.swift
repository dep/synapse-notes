import Foundation

struct MarkdownTablePrettifier {
    enum ColumnAlignment {
        case left, center, right
    }

    struct PrettifyResult {
        let formatted: String
        let cursorOffset: Int
    }

    /// Returns a prettified version of the table text, and the adjusted cursor offset
    /// within the new text. `cursorOffset` is relative to the start of the table block.
    /// `availableColumns` is the total character width of the editor (used to stretch columns to fill).
    static func prettify(tableText: String, cursorOffsetInTable: Int) -> PrettifyResult? {
        // Normalize CRLF / lone CR so trimming pipes and separator detection behave like LF-only text.
        let normalizedTable = tableText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalizedTable.components(separatedBy: "\n")
        let hadTrailingNewline = normalizedTable.hasSuffix("\n")
        if hadTrailingNewline, let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        guard lines.count >= 2 else { return nil }

        let parsedRows = lines.map { parseCells(from: $0) }
        guard !parsedRows[0].isEmpty else { return nil }
        let isSeparator = { (cells: [String]) -> Bool in
            cells.allSatisfy { c in
                let t = c.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && t.trimmingCharacters(in: CharacterSet(charactersIn: "-:")).isEmpty
            }
        }
        guard parsedRows.count > 1, isSeparator(parsedRows[1]) else { return nil }

        let alignments = parseAlignments(from: parsedRows[1])
        let columnCount = parsedRows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return nil }

        // Compute min content width per column (excluding separator row)
        var colWidths = Array(repeating: 3, count: columnCount)
        for (rowIndex, cells) in parsedRows.enumerated() {
            if rowIndex == 1 { continue } // separator
            for colIndex in 0..<min(cells.count, columnCount) {
                let content = cells[colIndex].trimmingCharacters(in: .whitespaces)
                colWidths[colIndex] = max(colWidths[colIndex], content.count)
            }
        }

        // Build new lines
        var newLines: [String] = []
        for (rowIndex, cells) in parsedRows.enumerated() {
            if rowIndex == 1 {
                newLines.append(buildSeparatorRow(alignments: alignments, colWidths: colWidths))
            } else {
                newLines.append(buildDataRow(cells: cells, alignments: alignments, colWidths: colWidths))
            }
        }

        let formatted = newLines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        let adjustedCursor = adjustCursorOffset(
            oldLines: lines,
            newLines: newLines,
            cursorOffsetInTable: cursorOffsetInTable
        )
        return PrettifyResult(formatted: formatted, cursorOffset: adjustedCursor)
    }

    // MARK: - Cell parsing

    static func parseCells(from line: String) -> [String] {
        var s = line
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.components(separatedBy: "|")
    }

    // MARK: - Alignment detection

    private static func parseAlignments(from cells: [String]) -> [ColumnAlignment] {
        cells.map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            let isLeft = t.hasPrefix(":")
            let isRight = t.hasSuffix(":")
            if isLeft && isRight { return .center }
            if isRight { return .right }
            return .left
        }
    }

    // MARK: - Row builders

    private static func buildDataRow(cells: [String], alignments: [ColumnAlignment], colWidths: [Int]) -> String {
        var parts: [String] = []
        for colIndex in 0..<colWidths.count {
            let content = colIndex < cells.count ? cells[colIndex].trimmingCharacters(in: .whitespaces) : ""
            let width = colWidths[colIndex]
            let alignment = colIndex < alignments.count ? alignments[colIndex] : .left
            parts.append(" " + pad(content, to: width, alignment: alignment) + " ")
        }
        return "|" + parts.joined(separator: "|") + "|"
    }

    private static func buildSeparatorRow(alignments: [ColumnAlignment], colWidths: [Int]) -> String {
        var parts: [String] = []
        for colIndex in 0..<colWidths.count {
            let width = colWidths[colIndex]
            let alignment = colIndex < alignments.count ? alignments[colIndex] : .left
            let dashes = String(repeating: "-", count: width)
            switch alignment {
            case .left:    parts.append(" " + dashes + " ")
            case .right:   parts.append(" " + dashes + ": ")
            case .center:  parts.append(" :" + dashes + ": ")
            }
        }
        return "|" + parts.joined(separator: "|") + "|"
    }

    private static func pad(_ text: String, to width: Int, alignment: ColumnAlignment) -> String {
        let len = text.count
        guard len < width else { return text }
        let padding = width - len
        switch alignment {
        case .left:
            return text + String(repeating: " ", count: padding)
        case .right:
            return String(repeating: " ", count: padding) + text
        case .center:
            let left = padding / 2
            let right = padding - left
            return String(repeating: " ", count: left) + text + String(repeating: " ", count: right)
        }
    }

    // MARK: - Cursor adjustment

    private static func adjustCursorOffset(oldLines: [String], newLines: [String], cursorOffsetInTable: Int) -> Int {
        // Walk line by line to find which line the cursor is on
        var offset = 0
        for (lineIndex, oldLine) in oldLines.enumerated() {
            let lineLen = oldLine.count + 1 // +1 for the \n
            if cursorOffsetInTable <= offset + lineLen || lineIndex == oldLines.count - 1 {
                // Cursor is on this line
                let posInLine = cursorOffsetInTable - offset
                guard lineIndex < newLines.count else {
                    // Line was removed — place at end of last new line
                    return newLines.map { $0.count + 1 }.reduce(0, +) - 1
                }
                let newLine = newLines[lineIndex]

                // Find what column the cursor was at in the old row
                let oldLine_ = oldLines[lineIndex]
                let clampedPos = min(posInLine, oldLine_.count)

                // Map the character position to a "pipe segment" in the old line
                let newPos = mapCursorPosition(oldLine: oldLine_, newLine: newLine, posInLine: clampedPos)

                // Add up newline lengths for all preceding lines
                var newOffset = 0
                for i in 0..<lineIndex {
                    newOffset += newLines[i].count + 1
                }
                return newOffset + newPos
            }
            offset += lineLen
        }
        return cursorOffsetInTable
    }

    private static func mapCursorPosition(oldLine: String, newLine: String, posInLine: Int) -> Int {
        // Find which pipe segment the cursor is in (0 = before first pipe, 1 = first cell, etc.)
        let oldNS = oldLine as NSString
        var pipeCount = 0
        var posInCell = 0
        var passedFirstPipe = false

        let pipe = ("|" as NSString).character(at: 0)

        for i in 0..<min(posInLine, oldNS.length) {
            let ch = oldNS.character(at: i)
            if ch == pipe {
                pipeCount += 1
                posInCell = 0
                passedFirstPipe = true
            } else if passedFirstPipe {
                posInCell += 1
            }
        }

        // Now find the same pipe segment in the new line
        let newNS = newLine as NSString
        var newPipeCount = 0
        var newPassedFirstPipe = false
        for i in 0..<newNS.length {
            let ch = newNS.character(at: i)
            if ch == pipe {
                newPipeCount += 1
                newPassedFirstPipe = true
                if newPipeCount == pipeCount && newPassedFirstPipe {
                    // We're at the right pipe — now advance by posInCell, clamped
                    let cellStart = i + 1
                    let remaining = newNS.length - cellStart
                    return cellStart + min(posInCell, remaining)
                }
            }
        }

        return min(posInLine, newNS.length)
    }

}
