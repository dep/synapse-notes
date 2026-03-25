import Foundation

struct MarkdownDocument: Equatable {
    let source: String
    let blocks: [MarkdownBlock]
}

struct MarkdownBlock: Equatable {
    let kind: MarkdownBlockKind
    let range: NSRange
    let contentRange: NSRange
    let inlineTokens: [MarkdownInlineToken]
}

enum MarkdownBlockKind: Equatable {
    case frontmatter
    case heading(level: Int)
    case paragraph
    case unorderedListItem(indent: Int)
    case orderedListItem(indent: Int, ordinal: Int)
    case taskListItem(indent: Int, isChecked: Bool)
    case blockquote
    case fencedCodeBlock(fence: String, infoString: String?)
    case table(columnCount: Int)
    case thematicBreak
}

struct MarkdownInlineToken: Equatable {
    let kind: MarkdownInlineTokenKind
    let range: NSRange
    let contentRange: NSRange
    let rawText: String
}

enum MarkdownInlineTokenKind: Equatable {
    case markdownLink(destination: String)
    case markdownImage(destination: String, caption: String)
    case wikiLink(destination: String, alias: String?)
    case embed(destination: String)
    case highlight
}

final class MarkdownDocumentParser {
    private struct Line {
        let text: String
        let start: Int
        let utf16Length: Int
    }

    private struct ParsedTask {
        let indent: Int
        let isChecked: Bool
        let contentStart: Int
    }

    private struct ParsedOrderedList {
        let indent: Int
        let ordinal: Int
        let contentStart: Int
    }

    private struct ParsedUnorderedList {
        let indent: Int
        let contentStart: Int
    }

    private static let headingRegex = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
    private static let markdownImageRegex = try? NSRegularExpression(pattern: "!\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let markdownLinkRegex = try? NSRegularExpression(pattern: "(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let wikiLinkRegex = try? NSRegularExpression(pattern: "(?<!!)\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]")
    private static let embedRegex = try? NSRegularExpression(pattern: "!\\[\\[([^\\]]+)\\]\\]")
    private static let highlightRegex = try? NSRegularExpression(pattern: "==([^=]+)==")

    func parse(_ source: String) -> MarkdownDocument {
        let lines = makeLines(for: source)
        guard !lines.isEmpty else {
            return MarkdownDocument(source: source, blocks: [])
        }

        var blocks: [MarkdownBlock] = []
        var index = 0

        if let frontmatterEnd = parseFrontmatterEnd(in: lines) {
            let blockRange = range(fromLine: 0, toLine: frontmatterEnd, in: lines)
            let contentStart = lines[0].start + lines[0].utf16Length + 1
            let contentEnd = lines[frontmatterEnd].start
            let contentRange = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
            let contentText = substring(source, range: contentRange)
            blocks.append(MarkdownBlock(
                kind: .frontmatter,
                range: blockRange,
                contentRange: contentRange,
                inlineTokens: inlineTokens(in: contentText, baseOffset: contentRange.location)
            ))
            index = frontmatterEnd + 1
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let block = parseHeading(line, source: source) {
                blocks.append(block)
                index += 1
                continue
            }

            if let (block, nextIndex) = parseFencedCodeBlock(startingAt: index, lines: lines, source: source) {
                blocks.append(block)
                index = nextIndex
                continue
            }

            if let (block, nextIndex) = parseTable(startingAt: index, lines: lines, source: source) {
                blocks.append(block)
                index = nextIndex
                continue
            }

            if isThematicBreak(line.text) {
                let range = NSRange(location: line.start, length: line.utf16Length)
                blocks.append(MarkdownBlock(kind: .thematicBreak, range: range, contentRange: range, inlineTokens: []))
                index += 1
                continue
            }

            if line.text.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let end = consumeContiguousLines(startingAt: index, lines: lines) {
                    !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.text.trimmingCharacters(in: .whitespaces).hasPrefix(">")
                }
                let range = range(fromLine: index, toLine: end, in: lines)
                let blockText = substring(source, range: range)
                blocks.append(MarkdownBlock(kind: .blockquote, range: range, contentRange: range, inlineTokens: inlineTokens(in: blockText, baseOffset: range.location)))
                index = end + 1
                continue
            }

            if let task = parseTaskList(line.text) {
                let range = NSRange(location: line.start, length: line.utf16Length)
                let contentRange = NSRange(location: line.start + task.contentStart, length: max(0, line.utf16Length - task.contentStart))
                let blockText = substring(source, range: contentRange)
                blocks.append(MarkdownBlock(
                    kind: .taskListItem(indent: task.indent, isChecked: task.isChecked),
                    range: range,
                    contentRange: contentRange,
                    inlineTokens: inlineTokens(in: blockText, baseOffset: contentRange.location)
                ))
                index += 1
                continue
            }

            if let ordered = parseOrderedList(line.text) {
                let range = NSRange(location: line.start, length: line.utf16Length)
                let contentRange = NSRange(location: line.start + ordered.contentStart, length: max(0, line.utf16Length - ordered.contentStart))
                let blockText = substring(source, range: contentRange)
                blocks.append(MarkdownBlock(
                    kind: .orderedListItem(indent: ordered.indent, ordinal: ordered.ordinal),
                    range: range,
                    contentRange: contentRange,
                    inlineTokens: inlineTokens(in: blockText, baseOffset: contentRange.location)
                ))
                index += 1
                continue
            }

            if let unordered = parseUnorderedList(line.text) {
                let range = NSRange(location: line.start, length: line.utf16Length)
                let contentRange = NSRange(location: line.start + unordered.contentStart, length: max(0, line.utf16Length - unordered.contentStart))
                let blockText = substring(source, range: contentRange)
                blocks.append(MarkdownBlock(
                    kind: .unorderedListItem(indent: unordered.indent),
                    range: range,
                    contentRange: contentRange,
                    inlineTokens: inlineTokens(in: blockText, baseOffset: contentRange.location)
                ))
                index += 1
                continue
            }

            if isPipeTableCandidate(line.text) {
                let range = NSRange(location: line.start, length: line.utf16Length)
                let blockText = substring(source, range: range)
                blocks.append(MarkdownBlock(kind: .paragraph, range: range, contentRange: range, inlineTokens: inlineTokens(in: blockText, baseOffset: range.location)))
                index += 1
                continue
            }

            let end = consumeParagraph(startingAt: index, lines: lines)
            let range = range(fromLine: index, toLine: end, in: lines)
            let blockText = substring(source, range: range)
            blocks.append(MarkdownBlock(kind: .paragraph, range: range, contentRange: range, inlineTokens: inlineTokens(in: blockText, baseOffset: range.location)))
            index = end + 1
        }

        return MarkdownDocument(source: source, blocks: blocks)
    }

    private func makeLines(for source: String) -> [Line] {
        let parts = source.components(separatedBy: "\n")
        guard !parts.isEmpty else { return [] }

        var lines: [Line] = []
        var offset = 0

        for (index, part) in parts.enumerated() {
            let length = (part as NSString).length
            lines.append(Line(text: part, start: offset, utf16Length: length))
            offset += length
            if index < parts.count - 1 || source.hasSuffix("\n") {
                offset += 1
            }
        }

        return lines
    }

    private func parseFrontmatterEnd(in lines: [Line]) -> Int? {
        guard let first = lines.first, first.text == "---" else { return nil }
        guard lines.count > 1 else { return nil }
        for index in 1..<lines.count where lines[index].text == "---" {
            return index
        }
        return nil
    }

    private func parseHeading(_ line: Line, source: String) -> MarkdownBlock? {
        let nsLine = line.text as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = Self.headingRegex?.firstMatch(in: line.text, options: [], range: fullRange) else { return nil }
        let hashes = match.range(at: 1)
        let content = match.range(at: 2)
        let range = NSRange(location: line.start, length: line.utf16Length)
        let contentRange = NSRange(location: line.start + content.location, length: content.length)
        let blockText = substring(source, range: contentRange)
        return MarkdownBlock(
            kind: .heading(level: hashes.length),
            range: range,
            contentRange: contentRange,
            inlineTokens: inlineTokens(in: blockText, baseOffset: contentRange.location)
        )
    }

    private func parseFencedCodeBlock(startingAt start: Int, lines: [Line], source: String) -> (MarkdownBlock, Int)? {
        guard let opening = fencedCodeInfo(for: lines[start].text) else { return nil }

        var end = start
        for index in (start + 1)..<lines.count {
            if isClosingFence(lines[index].text, matching: opening.fence) {
                end = index
                break
            }
            end = index
        }

        let range = range(fromLine: start, toLine: end, in: lines)
        let contentStart = lines[start].start + lines[start].utf16Length + (start < lines.count - 1 || source.hasSuffix("\n") ? 1 : 0)
        let contentEnd: Int
        if end > start, isClosingFence(lines[end].text, matching: opening.fence) {
            contentEnd = lines[end].start
        } else {
            contentEnd = range.location + range.length
        }
        let contentRange = NSRange(location: min(contentStart, contentEnd), length: max(0, contentEnd - min(contentStart, contentEnd)))
        return (
            MarkdownBlock(
                kind: .fencedCodeBlock(fence: opening.fence, infoString: opening.infoString),
                range: range,
                contentRange: contentRange,
                inlineTokens: []
            ),
            end + 1
        )
    }

    private func parseTable(startingAt start: Int, lines: [Line], source: String) -> (MarkdownBlock, Int)? {
        guard start + 1 < lines.count else { return nil }
        guard isPipeTableCandidate(lines[start].text), isPipeTableSeparator(lines[start + 1].text) else { return nil }

        let headerColumnCount = pipeTableCells(in: lines[start].text).count
        guard headerColumnCount > 0 else { return nil }

        var end = start + 1
        var cursor = start + 2
        while cursor < lines.count, isPipeTableCandidate(lines[cursor].text) {
            end = cursor
            cursor += 1
        }

        let range = range(fromLine: start, toLine: end, in: lines)
        let blockText = substring(source, range: range)
        return (
            MarkdownBlock(kind: .table(columnCount: headerColumnCount), range: range, contentRange: range, inlineTokens: inlineTokens(in: blockText, baseOffset: range.location)),
            end + 1
        )
    }

    private func consumeContiguousLines(startingAt start: Int, lines: [Line], predicate: (Line) -> Bool) -> Int {
        var index = start
        while index + 1 < lines.count, predicate(lines[index + 1]) {
            index += 1
        }
        return index
    }

    private func consumeParagraph(startingAt start: Int, lines: [Line]) -> Int {
        var index = start
        while index + 1 < lines.count {
            let next = lines[index + 1]
            let trimmed = next.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsNewBlock(next.text) || isPipeTableCandidate(next.text) {
                break
            }
            index += 1
        }
        return index
    }

    private func startsNewBlock(_ line: String) -> Bool {
        if isThematicBreak(line) || fencedCodeInfo(for: line) != nil || parseTaskList(line) != nil || parseOrderedList(line) != nil || parseUnorderedList(line) != nil {
            return true
        }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        if Self.headingRegex?.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private func range(fromLine start: Int, toLine end: Int, in lines: [Line]) -> NSRange {
        let startOffset = lines[start].start
        let endOffset = lines[end].start + lines[end].utf16Length
        return NSRange(location: startOffset, length: max(0, endOffset - startOffset))
    }

    private func fencedCodeInfo(for line: String) -> (fence: String, infoString: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.hasPrefix("```") {
            let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return ("```", info.isEmpty ? nil : info)
        }
        if trimmed.hasPrefix("~~~") {
            let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return ("~~~", info.isEmpty ? nil : info)
        }
        return nil
    }

    private func isClosingFence(_ line: String, matching fence: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == fence
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private func parseTaskList(_ line: String) -> ParsedTask? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index].isWhitespace {
            index += 1
        }
        guard index + 5 < chars.count else { return nil }
        guard chars[index] == "-" || chars[index] == "*" || chars[index] == "+" else { return nil }
        guard chars[index + 1] == " " && chars[index + 2] == "[" else { return nil }
        let checkChar = chars[index + 3]
        guard checkChar == " " || checkChar == "x" || checkChar == "X" else { return nil }
        guard chars[index + 4] == "]" && chars[index + 5] == " " else { return nil }
        return ParsedTask(indent: index, isChecked: checkChar == "x" || checkChar == "X", contentStart: index + 6)
    }

    private func parseOrderedList(_ line: String) -> ParsedOrderedList? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index].isWhitespace {
            index += 1
        }
        var digits = ""
        while index < chars.count, chars[index].isNumber {
            digits.append(chars[index])
            index += 1
        }
        guard !digits.isEmpty, index + 1 < chars.count, chars[index] == ".", chars[index + 1] == " ", let ordinal = Int(digits) else {
            return nil
        }
        return ParsedOrderedList(indent: line.prefix { $0.isWhitespace }.count, ordinal: ordinal, contentStart: index + 2)
    }

    private func parseUnorderedList(_ line: String) -> ParsedUnorderedList? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index].isWhitespace {
            index += 1
        }
        guard index + 1 < chars.count else { return nil }
        guard chars[index] == "-" || chars[index] == "*" || chars[index] == "+" else { return nil }
        guard chars[index + 1] == " " else { return nil }
        return ParsedUnorderedList(indent: index, contentStart: index + 2)
    }

    private func isPipeTableCandidate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 2
    }

    private func isPipeTableSeparator(_ line: String) -> Bool {
        let cells = pipeTableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return core.count >= 1 && core.allSatisfy { $0 == "-" }
        }
    }

    private func pipeTableCells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
    }

    private func inlineTokens(in text: String, baseOffset: Int) -> [MarkdownInlineToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var tokens: [MarkdownInlineToken] = []

        Self.markdownImageRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let caption = nsText.substring(with: match.range(at: 1))
            let destination = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            tokens.append(MarkdownInlineToken(
                kind: .markdownImage(destination: destination, caption: caption),
                range: offset(match.range(at: 0), by: baseOffset),
                contentRange: offset(match.range(at: 1), by: baseOffset),
                rawText: nsText.substring(with: match.range(at: 0))
            ))
        }

        Self.embedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let tokenRange = offset(match.range(at: 0), by: baseOffset)
            let contentRange = offset(match.range(at: 1), by: baseOffset)
            tokens.append(MarkdownInlineToken(
                kind: .embed(destination: nsText.substring(with: match.range(at: 1))),
                range: tokenRange,
                contentRange: contentRange,
                rawText: nsText.substring(with: match.range(at: 0))
            ))
        }

        Self.wikiLinkRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let destination = nsText.substring(with: match.range(at: 1))
            let aliasRange = match.numberOfRanges > 2 ? match.range(at: 2) : NSRange(location: NSNotFound, length: 0)
            let alias = aliasRange.location == NSNotFound ? nil : nsText.substring(with: aliasRange)
            let visibleRange = aliasRange.location == NSNotFound ? match.range(at: 1) : aliasRange
            tokens.append(MarkdownInlineToken(
                kind: .wikiLink(destination: destination, alias: alias),
                range: offset(match.range(at: 0), by: baseOffset),
                contentRange: offset(visibleRange, by: baseOffset),
                rawText: nsText.substring(with: match.range(at: 0))
            ))
        }

        Self.markdownLinkRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let destination = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            tokens.append(MarkdownInlineToken(
                kind: .markdownLink(destination: destination),
                range: offset(match.range(at: 0), by: baseOffset),
                contentRange: offset(match.range(at: 1), by: baseOffset),
                rawText: nsText.substring(with: match.range(at: 0))
            ))
        }

        Self.highlightRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            guard contentRange.length > 0 else { return }
            tokens.append(MarkdownInlineToken(
                kind: .highlight,
                range: offset(match.range(at: 0), by: baseOffset),
                contentRange: offset(contentRange, by: baseOffset),
                rawText: nsText.substring(with: match.range(at: 0))
            ))
        }

        return tokens.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private func offset(_ range: NSRange, by amount: Int) -> NSRange {
        NSRange(location: range.location + amount, length: range.length)
    }

    private func substring(_ text: String, range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        let nsText = text as NSString
        guard range.location >= 0, range.location + range.length <= nsText.length else { return "" }
        return nsText.substring(with: range)
    }
}
