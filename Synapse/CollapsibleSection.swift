import Foundation

/// Represents a collapsible section in markdown text
struct CollapsibleSection: Identifiable, Equatable {
    let id = UUID()
    let headerRange: NSRange
    let contentRange: NSRange
    var isCollapsed: Bool
    /// The verbatim text of the header line (e.g. "- 11:20 Presentation").
    /// Used as a content-stable identifier so that edits above the section
    /// don't change the key and unexpectedly reset collapse state.
    let headerText: String

    /// Toggle the collapsed state
    mutating func toggle() {
        isCollapsed.toggle()
    }

    /// Return the full text with content hidden when collapsed.
    /// Uses NSString offsets (UTF-16) throughout to match NSRange semantics.
    func getVisibleText(from fullText: String) -> String {
        guard isCollapsed else { return fullText }

        let ns = fullText as NSString
        let totalLength = ns.length
        let contentStart = contentRange.location
        let contentEnd = contentRange.location + contentRange.length

        guard contentEnd <= totalLength else { return fullText }

        let before = ns.substring(with: NSRange(location: 0, length: contentStart))
        let after = contentEnd < totalLength
            ? ns.substring(from: contentEnd)
            : ""

        return before + after
    }

    /// A content-stable identifier: the header line text.
    /// This is unaffected by edits above the section in the document.
    func getIdentifier() -> String {
        return headerText
    }

    /// Number of lines (including blank lines) inside the content range of the
    /// full document text.  Returns 0 when `contentRange.length == 0`.
    func contentLineCount(in fullText: String) -> Int {
        guard contentRange.length > 0 else { return 0 }
        let ns = fullText as NSString
        let totalLength = ns.length
        let safeEnd = min(contentRange.location + contentRange.length, totalLength)
        guard safeEnd > contentRange.location else { return 0 }
        let slice = ns.substring(with: NSRange(location: contentRange.location,
                                               length: safeEnd - contentRange.location))
        // Split on newlines; a trailing newline produces an empty final component —
        // don't count it as an extra line.
        var lines = slice.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.count
    }
}

/// Parses markdown text to identify collapsible sections.
class CollapsibleSectionParser {

    /// Parse text and return all sections that have indented content below a list item.
    func parse(_ text: String) -> [CollapsibleSection] {
        var sections: [CollapsibleSection] = []
        let lines = text.components(separatedBy: .newlines)

        // Build UTF-16 start offsets for every line.
        var lineStartOffsets: [Int] = []
        var offset = 0
        for (index, line) in lines.enumerated() {
            lineStartOffsets.append(offset)
            offset += (line as NSString).length
            // Add 1 for the newline separator, except after the last line when
            // the text itself doesn't end with a newline.
            if index < lines.count - 1 || text.hasSuffix("\n") {
                offset += 1
            }
        }

        for (lineIndex, line) in lines.enumerated() {
            // A collapsible header must start with "- " followed by a non-whitespace char.
            guard isListItem(line) else { continue }

            let headerLength = (line as NSString).length
            let headerRange = NSRange(location: lineStartOffsets[lineIndex], length: headerLength)

            if let contentRange = findIndentedContent(
                startingAt: lineIndex + 1,
                in: lines,
                lineStartOffsets: lineStartOffsets,
                text: text
            ) {
                sections.append(CollapsibleSection(
                    headerRange: headerRange,
                    contentRange: contentRange,
                    isCollapsed: false,
                    headerText: line
                ))
            } else {
                // Still register the section, with an empty content range, so
                // callers can observe that no indented content follows.
                sections.append(CollapsibleSection(
                    headerRange: headerRange,
                    contentRange: NSRange(location: lineStartOffsets[lineIndex] + headerLength, length: 0),
                    isCollapsed: false,
                    headerText: line
                ))
            }
        }

        return sections
    }

    // MARK: - Private helpers

    private func isListItem(_ line: String) -> Bool {
        guard line.hasPrefix("- ") else { return false }
        let afterPrefix = line.dropFirst(2)
        guard let first = afterPrefix.first else { return false }
        return !first.isWhitespace
    }

    /// Returns the NSRange (UTF-16) of the indented block following the given
    /// start line, or nil if there is no indented content.
    ///
    /// The range extends through the last *non-blank* indented line plus its
    /// trailing newline (if present).  Blank lines within an indented block are
    /// allowed, but trailing blank lines are excluded from the range.
    private func findIndentedContent(
        startingAt startLine: Int,
        in lines: [String],
        lineStartOffsets: [Int],
        text: String
    ) -> NSRange? {
        guard startLine < lines.count else { return nil }

        var lastIndentedLine: Int? = nil

        for i in startLine..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // Blank line: keep scanning but don't extend lastIndentedLine yet
                continue
            } else if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Indented non-blank content
                lastIndentedLine = i
            } else {
                // Non-indented, non-blank: stop
                break
            }
        }

        guard let lastLine = lastIndentedLine else { return nil }

        let startOffset = lineStartOffsets[startLine]
        let lastLineStart = lineStartOffsets[lastLine]
        let lastLineUTF16Length = (lines[lastLine] as NSString).length
        var endOffset = lastLineStart + lastLineUTF16Length

        // Include the trailing newline after the last content line, if present.
        let nsText = text as NSString
        if endOffset < nsText.length {
            let ch = nsText.character(at: endOffset)
            if ch == UInt16(("\n" as UnicodeScalar).value) {
                endOffset += 1
            }
        }

        return NSRange(location: startOffset, length: endOffset - startOffset)
    }
}

/// Manages per-file collapsed state (in-memory; not persisted to disk).
class CollapsibleStateManager {
    private var state: [String: Set<String>] = [:] // filePath -> collapsed section IDs
    /// Tracks files for which explicit state has been recorded this session.
    /// Used to distinguish "file never opened" from "file opened, all sections expanded".
    private var seenFiles: Set<String> = []

    func isCollapsed(_ sectionId: String, in file: URL) -> Bool {
        return state[file.path]?.contains(sectionId) ?? false
    }

    func setCollapsed(_ collapsed: Bool, for sectionId: String, in file: URL) {
        if state[file.path] == nil {
            state[file.path] = Set()
        }
        if collapsed {
            state[file.path]?.insert(sectionId)
        } else {
            state[file.path]?.remove(sectionId)
        }
        seenFiles.insert(file.path)
    }

    /// Returns true if any explicit collapse/expand decision has been recorded
    /// for this file during the current session.
    func hasSessionState(for file: URL) -> Bool {
        return seenFiles.contains(file.path)
    }

    func getCollapsedSections(in file: URL) -> Set<String> {
        return state[file.path] ?? Set()
    }

    func clearState(for file: URL) {
        state.removeValue(forKey: file.path)
        seenFiles.remove(file.path)
    }
}
