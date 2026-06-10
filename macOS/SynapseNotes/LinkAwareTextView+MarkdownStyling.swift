import SwiftUI
import AppKit

/// Custom attribute key for wiki links — avoids NSTextView overriding our foreground color via linkTextAttributes.
extension NSAttributedString.Key {
    static let wikilinkTarget = NSAttributedString.Key("Synapse.wikilinkTarget")
    static let tagTarget = NSAttributedString.Key("Synapse.tagTarget")
    /// Marks a character range so `LinkAwareTextView.drawBackground(in:)` draws
    /// its background color across the full container width, not just the glyph bounds.
    /// The value must be an `NSColor`.
    static let codeBlockFullWidthBackground = NSAttributedString.Key("Synapse.codeBlockFullWidthBackground")
    /// Marks a character range as belonging to a blockquote so
    /// `LinkAwareTextView.drawBackground(in:)` can paint a decorative accent bar
    /// along the leading edge of every line in the range. Value must be an `NSColor`.
    static let blockquoteLeftBorder = NSAttributedString.Key("Synapse.blockquoteLeftBorder")
}

/// Thread-safe regex cache for markdown styling outside of LinkAwareTextView.
private var sharedRegexCache: [String: NSRegularExpression] = [:]

private func cachedRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
    let key = "\(pattern)|\(options.rawValue)"
    if let cached = sharedRegexCache[key] { return cached }
    guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    sharedRegexCache[key] = compiled
    return compiled
}

/// Styles markdown text and returns an attributed string for display
func styleMarkdownContent(_ content: String, fontSize: CGFloat = 12) -> NSAttributedString {
    let storage = NSTextStorage(string: content)
    let text = content as NSString
    let fullRange = NSRange(location: 0, length: text.length)

    let baseFont = NSFont.systemFont(ofSize: fontSize)
    storage.addAttributes([
        .font: baseFont,
        .foregroundColor: SynapseTheme.editorForeground,
    ], range: fullRange)

    func applyPattern(_ pattern: String, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
        guard let regex = cachedRegex(pattern, options: options) else { return }
        regex.enumerateMatches(in: content, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            apply(range)
        }
    }

    func dimDelims(_ range: NSRange, _ delimLen: Int) {
        guard range.length >= delimLen * 2 else { return }
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location, length: delimLen))
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location + range.length - delimLen, length: delimLen))
    }

    // Headers
    let headerPatterns: [(String, NSFont)] = [
        ("^#{6} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^#{5} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^#{4} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^### .+$",  NSFont.systemFont(ofSize: fontSize + 4, weight: .bold)),
        ("^## .+$",   NSFont.systemFont(ofSize: fontSize + 6, weight: .bold)),
        ("^# .+$",    NSFont.systemFont(ofSize: fontSize + 8, weight: .bold)),
    ]
    for (pattern, font) in headerPatterns {
        applyPattern(pattern, options: [.anchorsMatchLines]) { range in
            storage.addAttributes([.font: font], range: range)
            let hashEnd = (text.substring(with: range) as NSString).range(of: "^#{1,6} ", options: .regularExpression)
            if hashEnd.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location + hashEnd.location, length: hashEnd.length))
            }
        }
    }

    // Italic — applied first so bold applied afterward wins on **word** spans
    applyPattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") { range in
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        if let f = NSFont(descriptor: desc, size: fontSize) {
            storage.addAttribute(.font, value: f, range: range)
        }
        dimDelims(range, 1)
    }
    // Bold — applied after italic so it wins over any italic applied to ** delimiters
    applyPattern("\\*\\*(.+?)\\*\\*") { range in
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: range)
        dimDelims(range, 2)
    }
    applyPattern("(?<![\\w_])_(?!_)(.+?)(?<!_)_(?![\\w_])") { range in
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        if let f = NSFont(descriptor: desc, size: fontSize) {
            storage.addAttribute(.font, value: f, range: range)
        }
        dimDelims(range, 1)
    }
    applyPattern("__(.+?)__") { range in
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: range)
        dimDelims(range, 2)
    }
    // Bold+italic — applied last so it wins over the bold and italic passes above on
    // ***word*** spans (which would otherwise collapse to plain bold).
    applyPattern("\\*\\*\\*(.+?)\\*\\*\\*") { range in
        let desc = NSFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withSymbolicTraits([.bold, .italic])
        let font = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        storage.addAttribute(.font, value: font, range: range)
        dimDelims(range, 3)
    }
    // Strikethrough — double first, then single with word-boundary guards.
    applyPattern("~~(.+?)~~") { range in
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        dimDelims(range, 2)
    }
    applyPattern("(?<![\\w~])~(?!~)(.+?)(?<!~)~(?![\\w~])") { range in
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        dimDelims(range, 1)
    }
    // Inline code
    applyPattern("`([^`\\n]+)`") { range in
        storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular), .backgroundColor: MarkdownTheme.codeBackground], range: range)
    }
    // Code blocks
    applyPattern("```[\\s\\S]*?```") { range in
        storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular), .backgroundColor: MarkdownTheme.codeBackground, .foregroundColor: SynapseTheme.editorForeground], range: range)
    }
    // Blockquotes
    applyPattern("^> .+$", options: [.anchorsMatchLines]) { range in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
    }
    // Inline tags
    AppState.inlineTagMatches(in: content).forEach { match in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.tagColor, range: match.range)
        storage.addAttribute(.tagTarget, value: match.normalized, range: match.range)
    }
    // Wiki links
    applyPattern("\\[\\[[^\\]]+\\]\\]") { range in
        guard range.length > 4 else { return }
        let inner = text.substring(with: NSRange(location: range.location + 2, length: range.length - 4))
        storage.addAttributes([.foregroundColor: MarkdownTheme.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, .link: inner], range: range)
    }
    // Markdown links
    applyPattern("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)") { range in
        // Need to re-match to get capture groups
        guard let regex = cachedRegex("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)") else { return }
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let full = match.range(at: 0)
            let label = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: full)
            storage.addAttributes([.foregroundColor: MarkdownTheme.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
        }
    }
    // Horizontal rules
    applyPattern("^---$", options: [.anchorsMatchLines]) { range in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
    }

    return NSAttributedString(attributedString: storage)
}

// MARK: - Markdown styling extension

extension LinkAwareTextView {
    func clearPendingWikilinkInsertion() {
        pendingWikilinkAlias = nil
        pendingWikilinkSelectionRange = nil
    }

    func setPlainText(_ plain: String) {
        guard let storage = textStorage else { return }
        // Tear down any in-flight/pending AI session BEFORE the storage is
        // replaced — stale ranges would corrupt the new note or crash on
        // accept/reject, and the floating bar would linger over new content.
        teardownAISession()
        // Stale ranges from a previous file would crash reapplySearchHighlights
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
        // New content invalidates the reveal memo (parse cache + revealed-block
        // gate) so the next caret move re-evaluates against the new document.
        previewRevealMemo.noteTextChanged()
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: plain))
        storage.endEditing()
        applyMarkdownStyling(deferRedraw: !isEditable)
        if !isEditable {
            applyPreviewStyling(editingSessionOpen: true)
        }
        // Note: hideMarkdownWhileEditing in editable mode is handled in the
        // Coordinator's styling callback and updateNSView, which have access to appState.
    }

    /// Called after applyMarkdownStyling() in view/preview mode.
    /// Hides markdown syntax tokens (delimiters, sigils, fences) by setting
    /// their font size to near-zero and foreground color to clear, so only the
    /// styled content is visible.
    func applyPreviewStyling(document: MarkdownDocument? = nil, refreshPlan: MarkdownEditorRefreshPlan = .fullDocument, editingSessionOpen: Bool = false) {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        let text = storage.string
        let parsedDocument = document ?? MarkdownDocumentParser().parse(text)
        let previewSemanticHiding = MarkdownPreviewSemanticHiding.make(from: parsedDocument, isEditable: isEditable)
        let scopeRange = refreshPlan.affectedRange ?? fullRange
        let searchRange = (text as NSString).lineRange(for: scopeRange)
        let fencedCodeBlockRanges = parsedDocument.blocks.compactMap { block -> NSRange? in
            if case .fencedCodeBlock = block.kind {
                return block.range
            }
            return nil
        }

        let hiddenAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 0.001),
            .foregroundColor: NSColor.clear,
        ]

        func hide(_ pattern: String, options: NSRegularExpression.Options = []) {
            guard let regex = cachedRegex(pattern, options: options) else { return }
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let range = match?.range else { return }
                storage.addAttributes(hiddenAttrs, range: range)
            }
        }

        func hideGroup(_ pattern: String, group: Int, options: NSRegularExpression.Options = []) {
            guard let regex = cachedRegex(pattern, options: options) else { return }
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let match, match.numberOfRanges > group else { return }
                let r = match.range(at: group)
                guard r.location != NSNotFound else { return }
                storage.addAttributes(hiddenAttrs, range: r)
            }
        }

        func isInsideFencedCodeBlock(_ range: NSRange) -> Bool {
            fencedCodeBlockRanges.contains { blockRange in
                NSIntersectionRange(blockRange, range).length > 0
            }
        }

        // applyMarkdownStyling() already ran before this and applied all fonts.
        // We only need to hide the markdown syntax tokens here.
        // Do NOT re-apply base fonts — that would undo the heading sizes set by applyMarkdownStyling.

        if !editingSessionOpen {
            storage.beginEditing()
        }

        for range in previewSemanticHiding.hiddenRanges where NSIntersectionRange(range, scopeRange).length > 0 {
            storage.addAttributes(hiddenAttrs, range: range)
        }

        for block in parsedDocument.blocks {
            guard case .fencedCodeBlock = block.kind else { continue }
            guard NSIntersectionRange(block.range, searchRange).length > 0 else { continue }

            let firstLineRange = (text as NSString).lineRange(for: NSRange(location: block.range.location, length: 0))
            let lastLineLocation = block.range.location + block.range.length - 1
            let lastLineRange = (text as NSString).lineRange(for: NSRange(location: lastLineLocation, length: 0))

            for lineRange in [firstLineRange, lastLineRange] {
                let paragraphStyle = (storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraphStyle.minimumLineHeight = 0
                paragraphStyle.maximumLineHeight = 0
                paragraphStyle.lineSpacing = 0
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }
        }

        // Bold **text** — hide the ** delimiters
        hideGroup("(\\*\\*)(.+?)(\\*\\*)", group: 1)
        hideGroup("(\\*\\*)(.+?)(\\*\\*)", group: 3)
        // Bold __text__ — hide the __ delimiters
        hideGroup("(__)(.+?)(__)", group: 1)
        hideGroup("(__)(.+?)(__)", group: 3)

        // Italic *text* — hide the * delimiters (not **)
        hideGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 1)
        hideGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 3)

        // Inline code `code` — hide the backtick delimiters
        if let regex = cachedRegex("(`)((?:[^`\\n])+)(`)") {
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let match, match.numberOfRanges > 3 else { return }
                let openRange = match.range(at: 1)
                let closeRange = match.range(at: 3)
                guard openRange.location != NSNotFound, closeRange.location != NSNotFound else { return }
                if isInsideFencedCodeBlock(match.range(at: 0)) {
                    return
                }
                storage.addAttributes(hiddenAttrs, range: openRange)
                storage.addAttributes(hiddenAttrs, range: closeRange)
            }
        }

        // Image embeds ![caption](url) — hide ![ and ](url), keep caption visible.
        // Only hide when caption is non-empty; if [] leave the full markdown visible.
        hideGroup("(!\\[)([^\\]]+)(\\]\\([^)]+\\))", group: 1)
        hideGroup("(!\\[)([^\\]]+)(\\]\\([^)]+\\))", group: 3)

        // Dim caption text for image embeds
        let imageCaptionRegex = cachedRegex("!\\[([^\\]]+)\\]\\([^)]+\\)")
        imageCaptionRegex?.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let captionRange = match.range(at: 1)
            guard captionRange.location != NSNotFound else { return }
            storage.addAttributes([
                .foregroundColor: MarkdownTheme.dimColor,
            ], range: captionRange)
        }

        storage.endEditing()
        requestImmediateRedraw(for: scopeRange)
        lastAppliedEditorDisplayMode = .preview
        refreshTaskCheckboxButtons()

        // After hiding, reveal the wikilink/image embed the cursor is currently inside.
        // NOTE: the *block* reveal is intentionally NOT triggered here. applyPreviewStyling
        // is a pure "hide everything" pass (also used for read-only rendering and initial
        // load, where the caret sits at 0 inside the first block). Block reveal is a
        // response to caret movement and is driven from textViewDidChangeSelection instead.
        if isEditable {
            revealSemanticInlineMarkdownAtCursor(document: parsedDocument)
            revealCalloutHeaderAtCursor(document: parsedDocument)
        }
    }

    private func revealCalloutHeaderAtCursor(document: MarkdownDocument? = nil) {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return }
        let parsedDocument = document ?? MarkdownDocumentParser().parse(storage.string)
        let callouts = parsedDocument.blocks.compactMap { MarkdownCalloutDetector.detect(in: $0, source: parsedDocument.source) }
        guard let callout = callouts.first(where: { NSLocationInRange(cursor, $0.headerRange) }) else { return }

        // Configured body font, not the fixed 15pt legacy constant (see
        // revealSemanticInlineMarkdownAtCursor for why).
        let visibleAttrs: [NSAttributedString.Key: Any] = [
            .font: settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body,
            .foregroundColor: MarkdownTheme.dimColor,
        ]
        storage.beginEditing()
        storage.addAttributes(visibleAttrs, range: callout.headerRange)
        storage.endEditing()
    }

    func revealSemanticInlineMarkdownAtCursor(document: MarkdownDocument? = nil) {
        guard isEditable, let storage = textStorage else { return }
        // Runs on every selection change: reuse the caller's parse, or the reveal
        // memo's cached document (re-parsed only when the text actually changed).
        let parsedDocument = document ?? previewRevealMemo.document(for: storage.string)
        let reveal = MarkdownPreviewCursorReveal.make(
            document: parsedDocument,
            cursorLocation: selectedRange().location,
            isEditable: isEditable
        )
        guard !reveal.revealedRanges.isEmpty else { return }

        // Use the configured body font, NOT the fixed 15pt legacy MarkdownTheme.body —
        // otherwise revealing a token shrinks it whenever the user's editor font ≠ 15.
        let visibleAttrs: [NSAttributedString.Key: Any] = [
            .font: settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body,
            .foregroundColor: MarkdownTheme.dimColor,
        ]

        storage.beginEditing()
        for range in reveal.revealedRanges {
            storage.addAttributes(visibleAttrs, range: range)
        }
        storage.endEditing()
    }

    /// Reveals the raw markdown syntax (dimmed) for the entire parsed block the caret
    /// is in, so editing always shows the syntax for the block being edited. Re-hiding
    /// of the block the caret *left* is handled by the next full applyPreviewStyling pass.
    /// No-ops when the caret stays within the same block as the previous call.
    func revealCurrentBlockMarkdownAtCursor(document: MarkdownDocument? = nil) {
        guard isEditable, let storage = textStorage else { return }
        let cursor = selectedRange().location
        // Block-change gating BEFORE any parsing: if the text is unchanged and the
        // caret is still inside the block we revealed last time, there is nothing new
        // to reveal — the common case for the 1–2 selection changes per keystroke.
        if previewRevealMemo.canSkipBlockReveal(cursorLocation: cursor) {
            return
        }
        // The optional `document` lets callers avoid an extra parse when they already
        // hold one (its `source` is authoritative); otherwise the reveal memo's cached
        // document is reused (re-parsed only when the text actually changed).
        let parsedDocument = document ?? previewRevealMemo.document(for: storage.string)
        let reveal = MarkdownPreviewBlockReveal.make(document: parsedDocument, cursorLocation: cursor, isEditable: isEditable)
        previewRevealMemo.noteRevealedBlock(reveal.blockRange)

        guard !reveal.revealedRanges.isEmpty else { return }

        // The hidden delimiters were zeroed to systemFont(0.001); restore a visible
        // body-sized font and dim color. Body font reads cleanly for every delimiter
        // kind (**, *, `, [, ]], #, ```); surrounding content keeps its own font from
        // applyMarkdownStyling.
        let revealFont = settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body

        storage.beginEditing()
        for range in reveal.revealedRanges {
            let safeLoc = max(0, min(range.location, storage.length))
            let safeLen = min(range.length, storage.length - safeLoc)
            guard safeLen > 0 else { continue }
            let safeRange = NSRange(location: safeLoc, length: safeLen)
            storage.addAttributes([
                .font: revealFont,
                .foregroundColor: MarkdownTheme.dimColor,
            ], range: safeRange)
        }
        storage.endEditing()
        requestImmediateRedraw(for: reveal.blockRange ?? NSRange(location: cursor, length: 0))
    }

    func applyMarkdownStyling(document: MarkdownDocument? = nil, refreshPlan: MarkdownEditorRefreshPlan = .fullDocument, deferRedraw: Bool = false) {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            lastAppliedEditorFontSignature = EditorFontSignature(settings: settings)
            lastAppliedEditorDisplayMode = .markdown
            clearInlineImagePreviews()
            clearTaskCheckboxButtons()
            for key in Array(collapsibleToggleButtons.keys) {
                collapsibleToggleButtons[key]?.removeFromSuperview()
            }
            collapsibleToggleButtons.removeAll()
            return
        }
        let text = storage.string as NSString
        let parsedDocument = document ?? MarkdownDocumentParser().parse(storage.string)
        let scopeRange = refreshPlan.affectedRange ?? fullRange
        let searchRange = text.lineRange(for: scopeRange)
        lastAppliedEditorDisplayMode = .markdown
        clearTaskCheckboxButtons()
        let semanticStyles = MarkdownEditorSemanticStyles.make(from: parsedDocument)
        let inlineSemanticStyles = MarkdownEditorInlineSemanticStyles.make(from: parsedDocument)

        storage.beginEditing()

        // Use settings-based fonts if available, otherwise fall back to defaults
        let bodyFont = settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body
        let monoFont = settings != nil ? MarkdownTheme.monoFont(for: settings!) : MarkdownTheme.mono
        let h1Font = settings != nil ? MarkdownTheme.h1Font(for: settings!) : MarkdownTheme.h1
        let h2Font = settings != nil ? MarkdownTheme.h2Font(for: settings!) : MarkdownTheme.h2
        let h3Font = settings != nil ? MarkdownTheme.h3Font(for: settings!) : MarkdownTheme.h3
        let h4Font = settings != nil ? MarkdownTheme.h4Font(for: settings!) : MarkdownTheme.h4
        let boldFont = settings != nil ? MarkdownTheme.boldFont(for: settings!) : NSFont.systemFont(ofSize: 15, weight: .bold)
        let italicFont = settings != nil ? MarkdownTheme.italicFont(for: settings!) : {
            let desc = MarkdownTheme.body.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: desc, size: 15) ?? MarkdownTheme.body
        }()
        let lineHeightMultiple = settings != nil ? MarkdownTheme.lineHeightMultiple(for: settings!) : 1.6
        let baseParagraphStyle = MarkdownTheme.paragraphStyle(font: bodyFont, lineHeightMultiple: lineHeightMultiple)

        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: SynapseTheme.editorForeground,
            .paragraphStyle: baseParagraphStyle,
        ], range: scopeRange)

        for heading in semanticStyles.headings {
            guard NSIntersectionRange(heading.range, scopeRange).length > 0 else { continue }
            let font: NSFont
            switch heading.level {
            case 1: font = h1Font
            case 2: font = h2Font
            case 3: font = h3Font
            default: font = h4Font
            }
            let headingParaStyle = MarkdownTheme.paragraphStyle(font: font, lineHeightMultiple: lineHeightMultiple)
            storage.addAttributes([.font: font, .paragraphStyle: headingParaStyle], range: heading.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: heading.markerRange)
        }

        // Italic first, bold second — bold must win on **word** spans.
        // The single-star italic regex would otherwise match the inner *word* of **word**
        // and overwrite the bold font after it was applied.
        applyRegex("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: italicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("\\*\\*(.+?)\\*\\*", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        // Single-underscore italic before double-underscore bold, same reason as * vs **.
        // Word-boundary guards prevent matching inside identifiers like snake_case.
        applyRegex("(?<![\\w_])_(?!_)(.+?)(?<!_)_(?![\\w_])", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: italicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("__(.+?)__", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        // Bold+italic last so it overrides the bold/italic font applied on inner substrings.
        let boldItalicFont = settings != nil ? MarkdownTheme.boldItalicFont(for: settings!) : {
            let desc = NSFont.systemFont(ofSize: 15, weight: .bold).fontDescriptor.withSymbolicTraits([.bold, .italic])
            return NSFont(descriptor: desc, size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .bold)
        }()
        applyRegex("\\*\\*\\*(.+?)\\*\\*\\*", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldItalicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 3)
        }
        // Strikethrough: ~~text~~ and single ~text~ (with guards so it doesn't hit ~/home or ~~~).
        applyRegex("~~(.+?)~~", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        applyRegex("(?<![\\w~])~(?!~)(.+?)(?<!~)~(?![\\w~])", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("`([^`\\n]+)`", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttributes([.font: monoFont, .backgroundColor: MarkdownTheme.codeBackground], range: range)
        }
        let codePad: CGFloat = 10
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for block in parsedDocument.blocks {
            guard case let .fencedCodeBlock(_, infoString) = block.kind else { continue }
            guard NSIntersectionRange(block.range, scopeRange).length > 0 else { continue }

            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: MarkdownTheme.codeBackground,
                .foregroundColor: SynapseTheme.editorForeground,
                // Marker read by drawBackground(in:) to extend the fill to full width.
                .codeBlockFullWidthBackground: MarkdownTheme.codeBackground,
            ], range: block.range)

            if SyntaxHighlighter.isSupportedLanguage(infoString) {
                SyntaxHighlighter.apply(
                    to: storage,
                    codeRange: block.contentRange,
                    language: infoString,
                    baseFont: monoFont,
                    isDarkMode: isDarkMode
                )
            }

            // Add bottom padding to the closing fence line so the code block has breathing room
            // and the copy button has space to sit in.
            let nsStr = text as NSString
            let firstLineRange = nsStr.lineRange(for: NSRange(location: block.range.location, length: 0))
            let firstParaStyle = (storage.attribute(.paragraphStyle, at: firstLineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            firstParaStyle.paragraphSpacingBefore = 0
            storage.addAttribute(.paragraphStyle, value: firstParaStyle, range: firstLineRange)
            // Last line of block → paragraphSpacing (after) and full-width background
            let lastLineRange = nsStr.lineRange(for: NSRange(location: block.range.location + block.range.length - 1, length: 0))
            let lastParaStyle = (storage.attribute(.paragraphStyle, at: lastLineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            lastParaStyle.paragraphSpacing = codePad
            lastParaStyle.tailIndent = 0
            lastParaStyle.lineBreakMode = .byWordWrapping
            storage.addAttribute(.paragraphStyle, value: lastParaStyle, range: lastLineRange)
        }
        for block in parsedDocument.blocks {
            guard case .table = block.kind else { continue }
            guard NSIntersectionRange(block.range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.font, value: monoFont, range: block.range)
        }
        let calloutRanges = Set(semanticStyles.callouts.map { "\($0.range.location):\($0.range.length)" })
        for range in semanticStyles.blockquotes {
            guard !calloutRanges.contains("\(range.location):\(range.length)") else { continue }
            guard NSIntersectionRange(range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
            // Indent the text so a colored accent bar can live in the gutter without
            // overlapping the glyphs. drawBackground(in:) paints the bar.
            let existing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let paraStyle = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paraStyle.firstLineHeadIndent = 16
            paraStyle.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: paraStyle, range: range)
            storage.addAttribute(.blockquoteLeftBorder, value: MarkdownTheme.linkColor, range: range)
        }
        for callout in semanticStyles.callouts {
            guard NSIntersectionRange(callout.range, scopeRange).length > 0 else { continue }
            let background = MarkdownTheme.codeBackground.blended(withFraction: 0.2, of: MarkdownTheme.linkColor) ?? MarkdownTheme.codeBackground
            storage.addAttributes([
                .backgroundColor: background,
                .foregroundColor: SynapseTheme.editorForeground,
            ], range: callout.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: callout.markerRange)
            if let titleRange = callout.titleRange {
                storage.addAttributes([
                    .font: boldFont,
                    .foregroundColor: MarkdownTheme.linkColor,
                ], range: titleRange)
            }
        }
        if let frontmatter = semanticStyles.frontmatter {
            if NSIntersectionRange(frontmatter.contentRange, scopeRange).length > 0 {
                // Use a static/fixed line height for frontmatter that doesn't change with user settings
                let frontmatterFont = NSFont.systemFont(ofSize: 11)
                let frontmatterParagraphStyle = MarkdownTheme.paragraphStyle(font: frontmatterFont, lineHeightMultiple: 1.2)
                storage.addAttributes([
                    .font: frontmatterFont,
                    .foregroundColor: SynapseTheme.editorMuted,
                    .paragraphStyle: frontmatterParagraphStyle,
                ], range: frontmatter.contentRange)
            }
            let openingFence = NSRange(location: frontmatter.range.location, length: min(3, frontmatter.range.length))
            let closingFence = NSRange(location: frontmatter.range.location + frontmatter.range.length - 3, length: min(3, frontmatter.range.length))
            if NSIntersectionRange(openingFence, scopeRange).length > 0 {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: openingFence)
            }
            if NSIntersectionRange(closingFence, scopeRange).length > 0 {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: closingFence)
            }
        }
        AppState.inlineTagMatches(in: storage.string).forEach { match in
            guard NSIntersectionRange(match.range, scopeRange).length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.tagColor, range: match.range)
            storage.addAttribute(.tagTarget, value: match.normalized, range: match.range)
        }
        let noteNames = Set(allFiles.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        for entry in inlineSemanticStyles.entries {
            guard NSIntersectionRange(entry.range, scopeRange).length > 0 || NSIntersectionRange(entry.contentRange, scopeRange).length > 0 else { continue }
            switch entry.kind {
            case let .embed(rawTarget):
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.dimColor,
                    .link: rawTarget,
                ], range: entry.range)
            case let .wikiLink(rawTarget, destination, _):
                let baseName = destination
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? destination
                let resolved = !noteNames.isEmpty && noteNames.contains(baseName.lowercased())
                storage.addAttributes([
                    .foregroundColor: resolved ? MarkdownTheme.linkColor : MarkdownTheme.unresolvedLinkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .wikilinkTarget: rawTarget,
                ], range: entry.range)
            case let .markdownLink(destination):
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: entry.range)
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: entry.contentRange)

                if let url = URL(string: destination), url.scheme != nil {
                    storage.addAttribute(.link, value: url, range: entry.range)
                }
            case .highlight:
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.3), range: entry.contentRange)
            }
        }

        if let bareURLRegex = LinkAwareTextView.bareURLRegex {
            bareURLRegex.enumerateMatches(in: storage.string, options: [], range: searchRange) { match, _, _ in
                guard let match else { return }
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { return }

                if storage.attribute(.link, at: range.location, effectiveRange: nil) != nil {
                    return
                }

                let rawURL = text.substring(with: range)
                guard let url = URL(string: rawURL) else { return }

                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: url,
                ], range: range)
            }
        }
        for range in semanticStyles.thematicBreaks {
            guard NSIntersectionRange(range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
        }

        // Image embeds are now shown only in sidebar, not inline
        // Skip adding paragraph spacing for inline image previews
        /*
        for match in self.visibleInlineImageMatches() {
            let paragraphStyle = (storage.attribute(.paragraphStyle, at: match.paragraphRange.location, effectiveRange: nil) as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            let updatedStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            updatedStyle.paragraphSpacing = max(updatedStyle.paragraphSpacing, self.inlinePreviewHeight(for: match.source))
            storage.addAttribute(.paragraphStyle, value: updatedStyle, range: match.paragraphRange)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: match.range)
        }
        */

        // Restore Apple Color Emoji on emoji characters after ALL font-setting passes.
        // Moving this here (rather than immediately after the blanket setAttributes reset)
        // prevents heading/bold/italic styling passes from overwriting the emoji font,
        // which was the root cause of the emoji flicker during typing.
        restoreEmojiFonts(in: storage, range: scopeRange, bodyFont: bodyFont)

        applyCollapsibleStyling(storage: storage)
        if !deferRedraw {
            storage.endEditing()
        }
        lastAppliedEditorFontSignature = EditorFontSignature(settings: settings)
        if !deferRedraw {
            requestImmediateRedraw(for: scopeRange)
        }
        reapplySearchHighlights()
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
            self?.refreshCollapsibleToggles()
            self?.refreshCodeBlockCopyButtons()
            self?.refreshAISparkle()
        }
    }

    // Compiled-once regex cache keyed by "pattern|options.rawValue"
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let bareURLRegex = try? NSRegularExpression(pattern: #"https?://[^"]+?(?=[\s)\]>]|$)"#)

    private func applyRegex(_ pattern: String, to text: NSString, storage _: NSTextStorage, options: NSRegularExpression.Options = [], searchRange: NSRange? = nil, apply: (NSRange) -> Void) {
        let cacheKey = "\(pattern)|\(options.rawValue)"
        let regex: NSRegularExpression
        if let cached = LinkAwareTextView.regexCache[cacheKey] {
            regex = cached
        } else if let compiled = try? NSRegularExpression(pattern: pattern, options: options) {
            LinkAwareTextView.regexCache[cacheKey] = compiled
            regex = compiled
        } else {
            return
        }
        let range = searchRange ?? NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            guard let range = match?.range else { return }
            apply(range)
        }
    }

    /// Re-apply Apple Color Emoji to emoji characters after a blanket font reset.
    /// `NSTextStorage.setAttributes` replaces the font on every character,
    /// including emoji — which need the Apple Color Emoji font to render.
    /// Without this pass emoji momentarily show a fallback glyph (`` ` ``) until
    /// Core Text resolves the substitution, causing visible flicker.
    private func restoreEmojiFonts(in storage: NSTextStorage, range: NSRange, bodyFont: NSFont) {
        let text = storage.string
        let nsRange = Range(range, in: text)
        guard let nsRange else { return }
        let emojiFont = NSFont(name: "Apple Color Emoji", size: bodyFont.pointSize)
            ?? NSFont.systemFont(ofSize: bodyFont.pointSize)

        // Walk composed character sequences; only touch those containing emoji scalars.
        var idx = nsRange.lowerBound
        while idx < nsRange.upperBound {
            let next = text.index(after: idx)
            // rangeOfComposedCharacterSequence gives us the full cluster
            let cluster = text[idx..<next]
            let isEmoji = cluster.unicodeScalars.contains { scalar in
                scalar.properties.isEmoji && scalar.value > 0x23F // skip small ASCII-range symbols like #, *, 0-9
            }
            if isEmoji {
                let charRange = NSRange(idx..<next, in: text)
                storage.addAttribute(.font, value: emojiFont, range: charRange)
            }
            idx = next
        }
    }

    private func dimDelimiters(storage: NSTextStorage, outerRange: NSRange, delimLen: Int) {
        guard outerRange.length >= delimLen * 2 else { return }
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location, length: delimLen))
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location + outerRange.length - delimLen, length: delimLen))
    }

    private func requestImmediateRedraw(for range: NSRange) {
        guard range.length > 0 else { return }
        if let layoutManager, let textContainer {
            layoutManager.invalidateDisplay(forCharacterRange: range)
            layoutManager.ensureLayout(for: textContainer)
            var redrawRect = layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: textContainer)
            redrawRect.origin.x += textContainerOrigin.x
            redrawRect.origin.y += textContainerOrigin.y
            if !redrawRect.isEmpty {
                setNeedsDisplay(redrawRect.insetBy(dx: -24, dy: -24))
            }
        }
        needsDisplay = true
        if range.length == (textStorage?.length ?? 0) {
            setNeedsDisplay(bounds)
        }
    }

    func shouldSkipIncrementalMarkdownRestyle(
        document: MarkdownDocument,
        refreshPlan: MarkdownEditorRefreshPlan,
        editedRange: NSRange
    ) -> Bool {
        guard case let .blockRange(blockRange) = refreshPlan.kind else { return false }
        guard let block = document.blocks.first(where: { NSEqualRanges($0.range, blockRange) }) else { return false }
        guard case .paragraph = block.kind, block.inlineTokens.isEmpty else { return false }

        let nsText = string as NSString
        guard nsText.length > 0 else { return false }

        let probeLocation = min(max(0, editedRange.location), max(0, nsText.length - 1))
        let probeLength = min(max(1, editedRange.length), nsText.length - probeLocation)
        let probeRange = NSRange(location: probeLocation, length: probeLength)
        let probeText = nsText.substring(with: probeRange)

        return !containsMarkdownTrigger(in: probeText)
    }

    private func containsMarkdownTrigger(in text: String) -> Bool {
        let triggerCharacters = CharacterSet(charactersIn: "*_`[]!~#>|-:/")
        return text.rangeOfCharacter(from: triggerCharacters) != nil
    }

    // MARK: - Collapsible section toggle buttons

    /// Applies collapsed-content hiding to the text storage and positions toggle arrow buttons.
    /// Must be called from within or after `applyMarkdownStyling` once layout is ready.
    func applyCollapsibleStyling(storage: NSTextStorage) {
        guard storage.length > 0 else { return }

        let text = storage.string
        let sections = collapsibleParser.parse(text)
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL

        // When the file has no session state yet, auto-initialise each section:
        // collapse it if it has >= 10 lines, expand it otherwise.
        if !collapsibleStateManager.hasSessionState(for: fileURL) {
            for section in sections {
                guard section.contentRange.length > 0 else { continue }
                let shouldCollapse = section.contentLineCount(in: text) >= 10
                collapsibleStateManager.setCollapsed(shouldCollapse,
                                                     for: section.getIdentifier(),
                                                     in: fileURL)
            }
        }

        for section in sections {
            let sectionId = section.getIdentifier()
            let isCollapsed = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)

            guard section.contentRange.length > 0 else { continue }
            let contentRange = section.contentRange

            // Safety: clamp to storage length
            let safeLocation = min(contentRange.location, storage.length)
            let safeLength = min(contentRange.length, storage.length - safeLocation)
            guard safeLength > 0 else { continue }
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            if isCollapsed {
                // Hide content: make it invisible and zero-height
                let hiddenStyle = NSMutableParagraphStyle()
                hiddenStyle.maximumLineHeight = 0.001
                hiddenStyle.minimumLineHeight = 0.001
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.001),
                    .paragraphStyle: hiddenStyle,
                ], range: safeRange)
            }
        }
    }

    /// Positions (or creates) a small arrow toggle button in the left margin of each
    /// collapsible section header line, and removes buttons for sections that no longer exist.
    func refreshCollapsibleToggles() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let text = string
        let sections = collapsibleParser.parse(text)
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL

        let activeKeys = Set(sections.map { $0.getIdentifier() })

        // Remove stale buttons
        for key in Array(collapsibleToggleButtons.keys) where !activeKeys.contains(key) {
            collapsibleToggleButtons[key]?.removeFromSuperview()
            collapsibleToggleButtons.removeValue(forKey: key)
        }

        for section in sections {
            guard section.contentRange.length > 0 else {
                // No indented content — remove button if present
                let key = section.getIdentifier()
                collapsibleToggleButtons[key]?.removeFromSuperview()
                collapsibleToggleButtons.removeValue(forKey: key)
                continue
            }

            let sectionId = section.getIdentifier()
            let isCollapsed = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)

            // Anchor the disclosure control to the list marker itself so it aligns
            // with the first visible line rather than the broader header range.
            let markerRange = NSRange(location: section.headerRange.location, length: 1)
            let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            var markerRect = layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
            markerRect.origin.x += textContainerOrigin.x
            markerRect.origin.y += textContainerOrigin.y

            let buttonSize: CGFloat = 28
            let buttonFrame = collapsibleToggleFrame(
                forMarkerRect: markerRect,
                textContainerOrigin: textContainerOrigin,
                buttonSize: buttonSize
            )

            let button: CollapsibleToggleButton
            if let existing = collapsibleToggleButtons[sectionId] {
                button = existing
            } else {
                button = CollapsibleToggleButton(frame: buttonFrame)
                addSubview(button)
                collapsibleToggleButtons[sectionId] = button
            }

            button.isCollapsed = isCollapsed
            button.frame = buttonFrame
            button.toolTip = isCollapsed ? "Expand section" : "Collapse section"

            // Use target/action — capture the identifier by value
            let capturedId = sectionId
            button.target = self
            button.action = #selector(collapsibleToggleTapped(_:))
            button.identifier = NSUserInterfaceItemIdentifier(capturedId)
        }
    }

    // MARK: - Inline AI editing

    /// Positions a single reused ✨ button just past the end of the caret's line content
    /// (or past the selection when text is selected). Anchors to the *used* width of the
    /// caret's line fragment, so on an empty line it sits next to the caret rather than
    /// at the far right of the text container. Cheap: one layout lookup, no parsing.
    func refreshAISparkle() {
        guard let layoutManager, let textContainer else { return }
        // Respect the user's show/hide preference (default on).
        guard settings?.showAISparkle ?? true else {
            aiSparkleButton?.isHidden = true
            return
        }
        let sel = selectedRange()
        let ns = string as NSString

        // The character index whose line we anchor to: selection end, or the caret.
        let anchorIndex = max(0, min(sel.length > 0 ? sel.location + sel.length : sel.location, ns.length))

        let fallbackLineHeight = layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
        var lineRect: NSRect
        if sel.length > 0 {
            // Non-empty selection: anchor just past the trailing edge of its glyphs.
            let selGlyphs = layoutManager.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
            lineRect = layoutManager.boundingRect(forGlyphRange: selGlyphs, in: textContainer)
        } else if anchorIndex == ns.length
                    && (ns.length == 0 || ns.substring(with: NSRange(location: ns.length - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil) {
            // Caret on the final empty line (empty doc, or after a trailing newline). The
            // layout manager tracks this as the "extra line fragment". Its used rect is
            // the caret position on that empty line.
            let extra = layoutManager.extraLineFragmentUsedRect
            if extra.height > 0 {
                lineRect = extra
            } else {
                lineRect = NSRect(x: 0, y: 0, width: 0, height: fallbackLineHeight)
            }
        } else {
            // Caret on a non-trailing (possibly empty) line: use that line fragment's USED
            // rect, whose width reflects the actual typeset content (≈ the caret x on an
            // empty line), not the full container width — which is what made the ✨ fly
            // off to the right.
            let glyphIndex = min(layoutManager.glyphIndexForCharacter(at: anchorIndex), max(0, layoutManager.numberOfGlyphs - 1))
            lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }

        var rect = lineRect
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let size: CGFloat = 18
        let frame = NSRect(x: rect.maxX + 6, y: rect.minY + (rect.height - size) / 2, width: size, height: size)

        let button: AISparkleButton
        if let existing = aiSparkleButton {
            button = existing
        } else {
            button = AISparkleButton(frame: frame)
            button.target = self
            button.action = #selector(aiSparkleTapped)
            addSubview(button)
            aiSparkleButton = button
        }
        // This runs on every caret move; avoid needless invalidation when nothing moved.
        if button.frame != frame { button.frame = frame }
        button.isHidden = (aiBarHostingView != nil)   // hide while the bar is open
    }

    @objc func aiSparkleTapped() {
        let sel = selectedRange()
        let mode: InlineAIBarMode = sel.length > 0 ? .rewrite : .generate
        presentAIBar(mode: mode, at: sel)
    }

    private func presentAIBar(mode: InlineAIBarMode, at sel: NSRange) {
        dismissAIBar()
        aiBarOriginalSelection = sel
        aiBarUserMoved = false
        aiBarDragStartOrigin = nil

        let defaultModel = AIModel(apiID: settings?.aiDefaultModel ?? AIModel.default.apiID)
        let model = InlineAIBarModel(mode: mode, model: defaultModel)
        model.allFiles = aiAppState?.allFiles ?? []
        model.allFolders = aiAppState?.allFolders() ?? []

        model.onSubmit = { [weak self] prompt, chosen in
            self?.startAIStream(prompt: prompt, model: chosen, mode: mode, selection: sel)
        }
        model.onRetry = { [weak self] prompt, chosen in
            // Discard the previous output so the re-run replaces it instead of
            // appending, then stream fresh from the original anchor/selection.
            self?.inlineAIController.discardOutput()
            self?.clearAIDiffColors()
            self?.aiBarModel?.awaitingAcceptReject = false
            self?.startAIStream(prompt: prompt, model: chosen, mode: mode, selection: sel)
        }
        model.onStop   = { [weak self] in self?.stopAIStream() }
        model.onAccept = { [weak self] in self?.acceptAI() }
        model.onReject = { [weak self] in self?.rejectAI() }
        model.onCancel = { [weak self] in self?.dismissAIBar() }
        model.onDrag = { [weak self] translation in self?.dragAIBar(by: translation) }
        model.onDragEnded = { [weak self] in self?.aiBarDragStartOrigin = nil }
        model.onContentSizeMayHaveChanged = { [weak self] in self?.resizeAIBarToFit() }
        aiBarModel = model

        let host = NSHostingView(rootView: InlineAIBarView(model: model))
        host.frame = aiBarFrame(below: sel)
        addSubview(host)
        aiBarHostingView = host
        refreshAISparkle()
    }

    /// Frame for the AI bar. Anchored just below the bottom of the affected region so it
    /// never overlaps the streamed text/diff (the region is the end of the streamed
    /// `newRange`/`originalRange` once streaming starts, else the selection/cursor). If
    /// placing it below would push it past the bottom of the visible viewport (a long
    /// diff), it is placed ABOVE the top of the affected region instead, so it stays on
    /// screen and still clears the diff.
    private func aiBarFrame(below sel: NSRange, size: NSSize? = nil) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let ns = string as NSString
        let barSize = size ?? aiBarFittedSize()
        let width = barSize.width
        let barHeight = barSize.height

        func yOffset(forCharacterIndex index: Int) -> (top: CGFloat, bottom: CGFloat) {
            let safe = max(0, min(index, ns.length))
            let gr = layoutManager.glyphRange(forCharacterRange: NSRange(location: safe, length: 0), actualCharacterRange: nil)
            var r = layoutManager.boundingRect(forGlyphRange: gr, in: textContainer)
            r.origin.y += textContainerOrigin.y
            return (r.minY, r.maxY)
        }

        // Bottom of the affected region (prefer streamed text) and top of it (for the
        // above-placement fallback).
        var bottomAnchor = sel.length > 0 ? sel.location + sel.length : sel.location
        if let nr = inlineAIController.newRange { bottomAnchor = max(bottomAnchor, NSMaxRange(nr)) }
        if let orig = inlineAIController.originalRange { bottomAnchor = max(bottomAnchor, NSMaxRange(orig)) }
        let topAnchor = min(sel.location, inlineAIController.originalRange?.location ?? sel.location)

        let belowY = yOffset(forCharacterIndex: bottomAnchor).bottom + 6
        let visible = enclosingScrollView?.documentVisibleRect ?? visibleRect

        // If the bar placed below would run past the visible area, place it above the region.
        if belowY + barHeight > visible.maxY {
            let aboveY = yOffset(forCharacterIndex: topAnchor).top - barHeight - 6
            let clampedY = max(visible.minY + 6, aboveY)
            return NSRect(x: 12, y: clampedY, width: width, height: barHeight)
        }
        return NSRect(x: 12, y: belowY, width: width, height: barHeight)
    }

    /// The bar's content-fitted size (drag handle + growing prompt + suggestion list),
    /// clamped to the editor width and a sane height range. fittingSize needs the
    /// target width set on the host first.
    private func aiBarFittedSize() -> NSSize {
        let width = min(bounds.width - 24, 520)
        var height: CGFloat = 80
        if let host = aiBarHostingView {
            host.frame.size.width = width
            let fitting = host.fittingSize.height
            if fitting > 0 { height = max(60, min(fitting, 360)) }
        }
        return NSSize(width: width, height: height)
    }

    /// Re-anchors the bar below the current affected region (called as text streams in
    /// and when streaming finishes) so it tracks the growing diff instead of covering it.
    /// No-op once the user has dragged the bar to a manual position.
    private func repositionAIBar() {
        guard let host = aiBarHostingView, !aiBarUserMoved else { return }
        // Streaming doesn't change the bar's content, so reuse its current size —
        // avoids a full SwiftUI fitting pass per streamed delta.
        host.frame = aiBarFrame(below: aiBarOriginalSelection, size: host.frame.size)
    }

    /// Resizes the bar to fit its content (prompt growth, suggestion list). Preserves the
    /// user-dragged origin if they moved it; otherwise re-anchors below the affected region.
    private func resizeAIBarToFit() {
        guard let host = aiBarHostingView else { return }
        if aiBarUserMoved {
            host.frame.size = aiBarFittedSize()
        } else {
            host.frame = aiBarFrame(below: aiBarOriginalSelection)
        }
    }

    /// Moves the bar by a drag-handle translation. The bar is a subview of the text view,
    /// which is a flipped NSView (y grows downward) — same direction as SwiftUI's global
    /// translation — so the y delta is ADDED, not negated. The translation is cumulative
    /// from drag start, so we offset the origin captured when the drag began.
    private func dragAIBar(by translation: CGSize) {
        guard let host = aiBarHostingView else { return }
        aiBarUserMoved = true
        let start = aiBarDragStartOrigin ?? host.frame.origin
        if aiBarDragStartOrigin == nil { aiBarDragStartOrigin = start }
        let newOrigin = NSPoint(x: start.x + translation.width,
                                y: start.y + translation.height)
        // Keep the bar within the visible area.
        let visible = enclosingScrollView?.documentVisibleRect ?? visibleRect
        let clampedX = min(max(newOrigin.x, visible.minX + 4), visible.maxX - host.frame.width - 4)
        let clampedY = min(max(newOrigin.y, visible.minY + 4), visible.maxY - host.frame.height - 4)
        host.frame.origin = NSPoint(x: clampedX, y: clampedY)
    }

    /// Shared teardown core: cancels any in-flight stream, closes the operation's
    /// single undo group, and removes the bar.
    private func cancelAIStreamAndRemoveBar() {
        aiStreamTask?.cancel(); aiStreamTask = nil
        endAIUndoGroup()
        aiBarHostingView?.removeFromSuperview(); aiBarHostingView = nil
        aiBarModel = nil
    }

    private func dismissAIBar() {
        cancelAIStreamAndRemoveBar()
        refreshAISparkle()
    }

    /// Tears down any in-flight or pending inline-AI session. Called when the
    /// document is swapped (note/tab switch) so stale ranges can't corrupt the
    /// new note or crash on accept/reject. Does NOT touch storage: the
    /// about-to-run setPlainText replaces the whole attributed string, so old
    /// diff colors vanish with it.
    func teardownAISession() {
        guard aiBarHostingView != nil || inlineAIController.mode != .idle else { return }
        cancelAIStreamAndRemoveBar()
        inlineAIController.resetWithoutMutating()
    }

    /// Re-applies transient AI diff colors after a styling pass, if a session is active.
    /// The normal markdown restyle blanket-sets foreground colors, wiping the diff
    /// colors; this restores them so they don't flicker mid-stream.
    func reapplyAIDiffColorsIfActive() {
        guard inlineAIController.mode != .idle else { return }
        applyAIDiffColors()
    }

    /// Applies an AI text mutation through the standard NSTextView edit path so it
    /// registers with the undo manager (Cmd-Z reverts AI insertions/rewrites). Bounds-safe.
    /// All edits in one AI operation are coalesced into a single undo group (see
    /// `beginAIUndoGroup`/`endAIUndoGroup`) so one Cmd-Z reverts the whole thing.
    private func performAIEdit(_ range: NSRange, _ replacement: String) {
        guard let storage = textStorage else { return }
        guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    /// Opens an undo group so every streamed delta + the accept/reject deletion collapse
    /// into a single Cmd-Z. Also disables NSTextView's automatic per-keystroke coalescing
    /// boundary so the deltas don't split into separate undo steps.
    private func beginAIUndoGroup() {
        guard !aiUndoGroupOpen else { return }
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        aiUndoGroupOpen = true
    }

    /// Closes the AI undo group opened by `beginAIUndoGroup` (idempotent).
    private func endAIUndoGroup() {
        guard aiUndoGroupOpen else { return }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        aiUndoGroupOpen = false
    }

    private func startAIStream(prompt: String, model: AIModel, mode: InlineAIBarMode, selection sel: NSRange) {
        guard let storage = textStorage else { return }
        guard let key = KeychainStore().get(), !key.isEmpty else {
            aiBarModel?.errorMessage = "Add your Anthropic API key in Settings →"
            return
        }

        // Reuse the vault lists captured when the bar was presented; allFolders()
        // walks every file's ancestor chain, so don't recompute it per submit.
        let resolver = AIContextResolver(
            allFiles: aiBarModel?.allFiles ?? [],
            allFolders: aiBarModel?.allFolders ?? [],
            readContents: { try? String(contentsOf: $0, encoding: .utf8) })
        let resolved = resolver.resolve(prompt: prompt)

        if mode == .generate {
            inlineAIController.beginGenerate(in: storage, at: sel.location)
        } else {
            inlineAIController.beginRewrite(in: storage, selection: sel)
        }
        // Route the controller's text mutations through the undo-registering path so the
        // whole AI edit is undoable with Cmd-Z (one logical change, not silent storage edits).
        inlineAIController.performEdit = { [weak self] range, replacement in
            self?.performAIEdit(range, replacement)
        }
        // Group every edit in this operation (all deltas + the accept/reject deletion)
        // into a single undo step. Idempotent, so Retry re-entry keeps the same group.
        beginAIUndoGroup()

        let selectionText = mode == .rewrite ? (string as NSString).substring(with: sel) : nil
        let body = AIRequestBuilder.build(
            mode: mode,
            prompt: prompt, noteText: string,
            selection: selectionText, context: resolved.blocks, model: model)

        aiBarModel?.isStreaming = true
        if resolved.truncated {
            aiBarModel?.errorMessage = "Context truncated to fit."
        } else if !resolved.missing.isEmpty {
            aiBarModel?.errorMessage = "\(resolved.missing.count) reference(s) not found."
        } else {
            aiBarModel?.errorMessage = nil
        }

        let client = AnthropicClient(apiKey: key)
        aiStreamTask = Task { [weak self] in
            do {
                for try await delta in client.stream(body: body) {
                    await MainActor.run {
                        // appendDelta routes through performAIEdit, which calls didChangeText().
                        self?.inlineAIController.appendDelta(delta)
                        self?.colorAIDelta(appendedLength: (delta as NSString).length)
                        self?.repositionAIBar()
                    }
                }
                await MainActor.run { self?.finishAIStream(mode: mode) }
            } catch {
                await MainActor.run { self?.handleAIError(error) }
            }
        }
    }

    private func stopAIStream() {
        aiStreamTask?.cancel(); aiStreamTask = nil
        // finishAIStream owns the per-mode end-of-session rules (generate: reset +
        // dismiss; rewrite: await accept/reject).
        finishAIStream(mode: aiBarModel?.mode ?? .generate)
    }

    private func finishAIStream(mode: InlineAIBarMode) {
        aiBarModel?.isStreaming = false
        if mode == .rewrite {
            aiBarModel?.awaitingAcceptReject = true
        } else {
            inlineAIController.cancel()
            dismissAIBar()
        }
        applyAIDiffColors()
        repositionAIBar()
    }

    private func handleAIError(_ error: Error) {
        aiBarModel?.isStreaming = false
        if let e = error as? AnthropicClient.ClientError {
            switch e {
            case .invalidKey: aiBarModel?.errorMessage = "Invalid API key — check Settings."
            case .server(let s): aiBarModel?.errorMessage = "Server error (\(s)). Try again."
            case .badResponse: aiBarModel?.errorMessage = "Unexpected response. Try again."
            }
        } else {
            aiBarModel?.errorMessage = "Network error. Try again."
        }
        if aiBarModel?.mode == .generate {
            inlineAIController.cancel()   // generate: reset to idle so a retry starts clean
        }
        if aiBarModel?.mode == .rewrite { aiBarModel?.awaitingAcceptReject = true }
    }

    /// Shared accept/reject epilogue: resolve the diff via the controller, restore
    /// normal styling, sync the final text to the binding, and close the bar.
    private func resolveAIRewrite(_ resolve: () -> Void) {
        resolve()
        clearAIDiffColors()
        didChangeText()
        dismissAIBar()
    }

    private func acceptAI() { resolveAIRewrite(inlineAIController.accept) }

    private func rejectAI() { resolveAIRewrite(inlineAIController.reject) }

    /// Colors only the newly appended streamed delta (green) — O(delta) per chunk
    /// instead of re-coloring the whole accumulated diff (O(total), quadratic over a
    /// stream). The first delta falls back to the full pass so the original range
    /// gets its strikethrough/red at the same moment it always has; later wipes by
    /// styling passes are restored by `reapplyAIDiffColorsIfActive`.
    private func colorAIDelta(appendedLength: Int) {
        guard let storage = textStorage,
              let nr = inlineAIController.newRange, appendedLength > 0 else { return }
        guard nr.length > appendedLength else {
            applyAIDiffColors()
            return
        }
        let sub = NSRange(location: NSMaxRange(nr) - appendedLength, length: appendedLength)
        guard sub.location >= 0, NSMaxRange(sub) <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: sub)
    }

    private func applyAIDiffColors() {
        guard let storage = textStorage else { return }
        if let orig = inlineAIController.originalRange, orig.length > 0,
           NSMaxRange(orig) <= storage.length {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: orig)
            storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: orig)
        }
        if let nr = inlineAIController.newRange, nr.length > 0,
           NSMaxRange(nr) <= storage.length {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: nr)
        }
    }

    private func clearAIDiffColors() {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.strikethroughStyle, range: full)
        refreshEditorForCurrentDisplayMode(self)
    }

    @objc private func collapsibleToggleTapped(_ sender: NSControl) {
        let sectionId = sender.identifier?.rawValue ?? ""
        guard !sectionId.isEmpty else { return }
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL
        let current = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)
        collapsibleStateManager.setCollapsed(!current, for: sectionId, in: fileURL)
        refreshEditorForCurrentDisplayMode(self)
    }

    private func clearInlineImagePreviews() {
        for key in Array(inlineImageViews.keys) {
            inlineImageViews[key]?.removeFromSuperview()
            inlineImageViews.removeValue(forKey: key)
        }

        for key in Array(inlineVideoViews.keys) {
            inlineVideoViews[key]?.removeFromSuperview()
            inlineVideoViews.removeValue(forKey: key)
        }

        clearCodeBlockCopyButtons()
    }

}
