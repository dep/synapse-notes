import Foundation

struct MarkdownPreviewRenderer {
    private let parser: MarkdownDocumentParser

    init(parser: MarkdownDocumentParser = MarkdownDocumentParser()) {
        self.parser = parser
    }

    func renderBody(from markdown: String) -> String {
        renderBody(from: parser.parse(markdown))
    }

    func renderBody(from document: MarkdownDocument) -> String {
        var result: [String] = []
        var index = 0

        while index < document.blocks.count {
            let block = document.blocks[index]

            switch block.kind {
            case .frontmatter:
                index += 1
            case let .heading(level):
                result.append(renderHeading(level: level, block: block, source: document.source))
                index += 1
            case .paragraph:
                result.append(renderParagraph(block: block, source: document.source))
                index += 1
            case .blockquote:
                result.append(renderBlockquote(block: block, source: document.source))
                index += 1
            case .fencedCodeBlock:
                result.append(renderCodeBlock(block: block, source: document.source))
                index += 1
            case let .table(columnCount):
                result.append(renderTable(block: block, source: document.source, columnCount: columnCount))
                index += 1
            case .thematicBreak:
                result.append("<hr>")
                index += 1
            case .unorderedListItem:
                let (html, nextIndex) = renderList(startingAt: index, in: document, kind: ListRenderKind.unordered)
                result.append(html)
                index = nextIndex
            case .orderedListItem:
                let (html, nextIndex) = renderList(startingAt: index, in: document, kind: ListRenderKind.ordered)
                result.append(html)
                index = nextIndex
            case .taskListItem:
                let (html, nextIndex) = renderList(startingAt: index, in: document, kind: ListRenderKind.task)
                result.append(html)
                index = nextIndex
            }
        }

        return result.joined(separator: "\n")
    }

    private enum ListRenderKind {
        case unordered
        case ordered
        case task
    }

    private func renderHeading(level: Int, block: MarkdownBlock, source: String) -> String {
        let inner = renderInlineText(in: source, range: block.contentRange, tokens: block.inlineTokens)
        return "<h\(level)>\(inner)</h\(level)>"
    }

    private func renderParagraph(block: MarkdownBlock, source: String) -> String {
        let inner = renderInlineText(in: source, range: block.contentRange, tokens: block.inlineTokens)
        return "<p>\(inner)</p>"
    }

    private func renderBlockquote(block: MarkdownBlock, source: String) -> String {
        if let callout = MarkdownCalloutDetector.detect(in: block, source: source) {
            return renderCallout(callout, source: source)
        }
        let raw = substring(source, range: block.range)
        let stripped = raw
            .components(separatedBy: "\n")
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("> ") {
                    return String(trimmed.dropFirst(2))
                }
                if trimmed == ">" {
                    return ""
                }
                if trimmed.hasPrefix(">") {
                    return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
            .joined(separator: "\n")
        return "<blockquote>\(renderLegacyInline(stripped).replacingOccurrences(of: "\n", with: "<br>"))</blockquote>"
    }

    private func renderCallout(_ callout: MarkdownCallout, source: String) -> String {
        let nsSource = source as NSString
        let headerText = substring(source, range: callout.headerRange)
        let lines = substring(source, range: callout.blockRange).components(separatedBy: "\n")
        let title = callout.titleRange.map { renderLegacyInline(nsSource.substring(with: $0)) } ?? callout.kind.capitalized

        let bodyLines = Array(lines.dropFirst()).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> ") {
                return String(trimmed.dropFirst(2))
            }
            if trimmed.hasPrefix(">") {
                return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return trimmed
        }.filter { !$0.isEmpty }

        let bodyHTML = renderLegacyInline(bodyLines.joined(separator: "\n")).replacingOccurrences(of: "\n", with: "<br>")
        let explicitTitle = callout.titleRange != nil ? title : renderLegacyInline(headerText)
        return "<blockquote class=\"callout callout-\(escapeAttribute(callout.kind))\"><div class=\"callout-title\">\(explicitTitle)</div><div class=\"callout-body\">\(bodyHTML)</div></blockquote>"
    }

    private func renderCodeBlock(block: MarkdownBlock, source: String) -> String {
        var raw = substring(source, range: block.contentRange)
        if raw.hasSuffix("\n") {
            raw.removeLast()
        }
        let code = escapeHTML(raw)
        return "<pre><code>\(code)</code></pre>"
    }

    private func renderTable(block: MarkdownBlock, source: String, columnCount: Int) -> String {
        let lines = substring(source, range: block.range).components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return "<p>\(escapeHTML(substring(source, range: block.range)))</p>" }

        var html = "<table>"
        html += "<thead><tr>"
        for cell in parseTableRow(lines[0], expectedCount: columnCount) {
            html += "<th>\(renderLegacyInline(cell))</th>"
        }
        html += "</tr></thead>"

        if lines.count > 2 {
            html += "<tbody>"
            for line in lines.dropFirst(2) {
                html += "<tr>"
                for cell in parseTableRow(line, expectedCount: columnCount) {
                    html += "<td>\(renderLegacyInline(cell))</td>"
                }
                html += "</tr>"
            }
            html += "</tbody>"
        }

        html += "</table>"
        return html
    }

    private struct ListItem {
        let indent: Int
        let html: String
        let isTask: Bool
        let charOffset: Int
    }

    private func renderList(startingAt start: Int, in document: MarkdownDocument, kind: ListRenderKind) -> (String, Int) {
        var rawItems: [ListItem] = []
        var index = start

        while index < document.blocks.count {
            let block = document.blocks[index]
            switch (kind, block.kind) {
            case let (.unordered, .unorderedListItem(indent)):
                let content = renderInlineText(in: document.source, range: block.contentRange, tokens: block.inlineTokens)
                rawItems.append(ListItem(indent: indent, html: "<li>\(content)</li>", isTask: false, charOffset: block.range.location))
            case let (.ordered, .orderedListItem(indent, _)):
                let content = renderInlineText(in: document.source, range: block.contentRange, tokens: block.inlineTokens)
                rawItems.append(ListItem(indent: indent, html: "<li>\(content)</li>", isTask: false, charOffset: block.range.location))
            case let (.task, .taskListItem(indent, isChecked)):
                let content = renderInlineText(in: document.source, range: block.contentRange, tokens: block.inlineTokens)
                let checked = isChecked ? " checked" : ""
                // The [ ] / [x] marker starts at indent + 2 within the block (after "- ")
                let markerOffset = block.range.location + indent + 2
                let checkboxHTML = "<input type=\"checkbox\"\(checked) data-offset=\"\(markerOffset)\" onclick=\"window.webkit.messageHandlers.toggleCheckbox.postMessage(\(markerOffset))\">"
                rawItems.append(ListItem(indent: indent, html: "<li class=\"task-item\">\(checkboxHTML) <span>\(content)</span></li>", isTask: true, charOffset: markerOffset))
            default:
                return (buildNestedList(items: rawItems, kind: kind), index)
            }
            index += 1
        }

        return (buildNestedList(items: rawItems, kind: kind), index)
    }

    private func buildNestedList(items: [ListItem], kind: ListRenderKind) -> String {
        guard !items.isEmpty else { return "" }
        let tag: String
        let cls: String
        switch kind {
        case .unordered: tag = "ul"; cls = ""
        case .ordered: tag = "ol"; cls = ""
        case .task: tag = "ul"; cls = " class=\"task-list\""
        }

        var result = ""
        var stack: [(tag: String, indent: Int)] = []

        func openList(indent: Int) {
            result += "<\(tag)\(cls)>"
            stack.append((tag, indent))
        }
        func closeList() {
            if let top = stack.popLast() {
                result += "</\(top.tag)>"
            }
        }

        for item in items {
            if stack.isEmpty {
                openList(indent: item.indent)
            } else if item.indent > stack.last!.indent {
                // Nest deeper — wrap in new list inside last <li> by stripping its closing tag
                if result.hasSuffix("</li>") {
                    result = String(result.dropLast(5))
                }
                openList(indent: item.indent)
            } else if item.indent < stack.last!.indent {
                // Pop back up
                while stack.count > 1 && item.indent <= stack.last!.indent {
                    closeList()
                    // Also close the li we left open when we nested
                    result += "</li>"
                }
            }
            result += item.html
        }

        while !stack.isEmpty { closeList() }
        return result
    }

    private func renderInlineText(in source: String, range: NSRange, tokens: [MarkdownInlineToken]) -> String {
        let nsSource = source as NSString
        guard range.location != NSNotFound, range.location + range.length <= nsSource.length else { return "" }
        let relevantTokens = tokens.filter { token in
            token.range.location >= range.location && token.range.location + token.range.length <= range.location + range.length
        }

        var result = ""
        var cursor = range.location

        for token in relevantTokens.sorted(by: { $0.range.location < $1.range.location }) {
            if token.range.location > cursor {
                result += renderLegacyInline(nsSource.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            }
            result += renderToken(token, source: source)
            cursor = token.range.location + token.range.length
        }

        let end = range.location + range.length
        if cursor < end {
            result += renderLegacyInline(nsSource.substring(with: NSRange(location: cursor, length: end - cursor)))
        }

        return result
    }

    private func renderToken(_ token: MarkdownInlineToken, source: String) -> String {
        let label = renderLegacyInline(substring(source, range: token.contentRange))

        switch token.kind {
        case let .markdownLink(destination):
            return "<a href=\"\(escapeAttribute(destination))\">\(label)</a>"
        case let .markdownImage(destination, caption):
            return "<img src=\"\(escapeAttribute(destination))\" alt=\"\(escapeAttribute(caption))\">"
        case let .wikiLink(destination, _):
            return "<a href=\"wikilink://\(escapeAttribute(destination))\" class=\"wikilink\">\(label)</a>"
        case .embed:
            return "<span class=\"embed\">\(label)</span>"
        }
    }

    private func parseTableRow(_ line: String, expectedCount: Int) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        var cells = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.count < expectedCount {
            cells.append(contentsOf: Array(repeating: "", count: expectedCount - cells.count))
        }
        return Array(cells.prefix(expectedCount))
    }

    private func renderLegacyInline(_ text: String) -> String {
        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "`" {
                let after = text.index(after: i)
                if let end = text[after...].firstIndex(of: "`") {
                    result += "<code>\(escapeHTML(String(text[after..<end])))</code>"
                    i = text.index(after: end)
                    continue
                }
            }

            if text[i...].hasPrefix("***"), let end = text[text.index(i, offsetBy: 3)...].range(of: "***") {
                let content = String(text[text.index(i, offsetBy: 3)..<end.lowerBound])
                result += "<strong><em>\(escapeHTML(content))</em></strong>"
                i = end.upperBound
                continue
            }

            if text[i...].hasPrefix("**"), let end = text[text.index(i, offsetBy: 2)...].range(of: "**") {
                let content = String(text[text.index(i, offsetBy: 2)..<end.lowerBound])
                result += "<strong>\(escapeHTML(content))</strong>"
                i = end.upperBound
                continue
            }

            if text[i...].hasPrefix("__"), let end = text[text.index(i, offsetBy: 2)...].range(of: "__") {
                let content = String(text[text.index(i, offsetBy: 2)..<end.lowerBound])
                result += "<strong>\(escapeHTML(content))</strong>"
                i = end.upperBound
                continue
            }

            if text[i...].hasPrefix("~~"), let end = text[text.index(i, offsetBy: 2)...].range(of: "~~") {
                let content = String(text[text.index(i, offsetBy: 2)..<end.lowerBound])
                result += "<del>\(escapeHTML(content))</del>"
                i = end.upperBound
                continue
            }

            if text[i] == "*" || text[i] == "_" {
                let marker = String(text[i])
                let after = text.index(after: i)
                if let end = text[after...].range(of: marker) {
                    let content = String(text[after..<end.lowerBound])
                    result += "<em>\(escapeHTML(content))</em>"
                    i = end.upperBound
                    continue
                }
            }

            switch text[i] {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(text[i])
            }
            i = text.index(after: i)
        }

        return result
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func substring(_ source: String, range: NSRange) -> String {
        let nsSource = source as NSString
        guard range.location != NSNotFound, range.location + range.length <= nsSource.length else { return "" }
        return nsSource.substring(with: range)
    }
}
