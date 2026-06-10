import SwiftUI
import AppKit
import ImageIO

#if DEBUG
private func debugLog(_ msg: String) {
    let line = "[Synapse] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/Synapse_debug.log") {
            if let fh = FileHandle(forWritingAtPath: "/tmp/Synapse_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: "/tmp/Synapse_debug.log", contents: data)
        }
    }

}
#else
@inline(__always) private func debugLog(_ msg: String) {}
#endif

// MARK: - LinkAwareTextView

class LinkAwareTextView: NSTextView {
    enum EditorDisplayMode {
        case markdown
        case preview
    }

    var allFiles: [URL] = []
    var onOpenFile: ((URL, Bool) -> Void)?
    var onOpenTag: ((String, Bool) -> Void)?  // (tag, openInNewTab)
    var onActivatePane: (() -> Void)?
    var onCreateNote: ((String, URL?) -> Void)?  // name, preferred directory
    var onOpenExternalURL: ((URL) -> Void)?  // External URL opening (defaults to NSWorkspace)
    var onSelectEmbed: ((String) -> Void)?  // embed ID when clicking on markdown
    var currentFileURL: URL?
    var onMatchCountUpdate: ((Int) -> Void)?
    /// Only the editor participating in global commands (current focused note) should react to
    /// find/replace notifications that mutate text. Mirrors `onMatchCountUpdate` gating.
    var participatesInGlobalSearch: Bool = false
    var onWikiLinkRequest: (() -> Void)?   // Called when [[ is typed
    var onWikiLinkComplete: ((URL) -> Void)?  // Called when a file is selected for wiki link
    var onWikiLinkDismiss: (() -> Void)?   // Called when the picker is dismissed via ESC
    var slashCommandNowProvider: () -> Date = Date.init
    var slashCommandTimeZone: TimeZone = .current
    /// Called when CMD-K fires but the editor has no selection, so the normal command palette should open.
    var onCommandPaletteFallback: (() -> Void)?

    // Settings manager for font configuration
    var settings: SettingsManager?
    var lastAppliedEditorFontSignature: EditorFontSignature? = nil

    private var completionPopover: NSPopover?
    private var completionVC: CompletionViewController?
    fileprivate var linkTypingRange: NSRange?
    /// Set when the user ESCs the wiki-link picker. Suppresses reopening the picker
    /// until the cursor leaves the current [[ token (which calls dismissCompletion).
    var wikilinkPickerSuppressed = false
    /// Selected text captured before the wikilink palette opens; used to produce [[name|alias]].
    var pendingWikilinkAlias: String? = nil
    /// Original selection captured before the wikilink palette steals focus.
    var pendingWikilinkSelectionRange: NSRange? = nil
    var lastAppliedEditorDisplayMode: EditorDisplayMode? = nil
    private var eventMonitor: Any?
    var inlineImageViews: [String: NSImageView] = [:]
    var inlineVideoViews: [String: YouTubePreviewView] = [:]
    private var isPrettifyingTable = false

    // MARK: - Collapsible sections
    let collapsibleParser = CollapsibleSectionParser()
    let collapsibleStateManager = CollapsibleStateManager()
    /// Toggle buttons keyed by section identifier ("headerOffset-headerLength")
    var collapsibleToggleButtons: [String: CollapsibleToggleButton] = [:]

    // MARK: - Inline AI editing
    let inlineAIController = InlineAIController()
    /// True while a rewrite diff is on screen awaiting accept/reject — the buffer
    /// holds both original and new text, which must not be synced/saved as-is.
    var hasPendingAIDiff: Bool { inlineAIController.mode == .rewrite }
    var aiSparkleButton: AISparkleButton?
    var aiBarHostingView: NSHostingView<InlineAIBarView>?
    var aiBarModel: InlineAIBarModel?
    var aiStreamTask: Task<Void, Never>?
    /// The selection/cursor captured when the bar opened — used to re-anchor the bar
    /// below the affected region as text streams in.
    var aiBarOriginalSelection: NSRange = NSRange(location: 0, length: 0)
    /// The bar's origin captured at the start of a drag (nil when not dragging).
    var aiBarDragStartOrigin: NSPoint?
    /// Once the user drags the bar, stop auto-repositioning it below the streamed text.
    var aiBarUserMoved = false
    /// True while an AI undo group is open (so the whole operation undoes as one step).
    var aiUndoGroupOpen = false
    /// Injected at setup; source of vault files for @-context.
    weak var aiAppState: AppState?

    // MARK: - Embedded Notes (for side panel)
    private static let embedRegex = try? NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)

    private static let inlineImageRegex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\((.+?)\)"#, options: [])

    /// Extends code-block background fills to the full container width.
    /// NSAttributedString's .backgroundColor only covers the glyph bounds for that run.
    /// For the closing fence line the background stops at the last visible glyph,
    /// leaving a gap on the right. We intercept drawBackground and repaint any run
    /// that carries the custom `.codeBlockFullWidthBackground` marker attribute as a
    /// full-width band.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let containerWidth = textContainer.containerSize.width
        let insetX = textContainerOrigin.x
        let insetY = textContainerOrigin.y

        var charIndex = 0
        let length = storage.length
        while charIndex < length {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            guard let color = storage.attribute(.codeBlockFullWidthBackground, at: charIndex, effectiveRange: &effectiveRange) as? NSColor,
                  effectiveRange.location != NSNotFound else {
                charIndex = effectiveRange.location != NSNotFound ? effectiveRange.location + effectiveRange.length : charIndex + 1
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
            var lineStart = glyphRange.location
            let glyphEnd = glyphRange.location + glyphRange.length

            while lineStart < glyphEnd {
                var lineGlyphRange = NSRange(location: NSNotFound, length: 0)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineStart, effectiveRange: &lineGlyphRange, withoutAdditionalLayout: true)
                guard lineGlyphRange.location != NSNotFound else { break }

                let bandY = lineRect.origin.y + insetY
                let bandHeight = lineRect.height
                guard bandHeight > 0 else {
                    lineStart = lineGlyphRange.location + lineGlyphRange.length
                    continue
                }

                let bandRect = NSRect(x: insetX, y: bandY, width: containerWidth, height: bandHeight)
                if bandRect.intersects(rect) {
                    color.setFill()
                    bandRect.fill()
                }
                lineStart = lineGlyphRange.location + lineGlyphRange.length
            }
            charIndex = effectiveRange.location + effectiveRange.length
        }

        // Decorative accent bar for blockquote ranges. Paragraph style supplies the
        // leading indent (16pt); we paint a rounded bar of ~3pt in that gutter.
        let barWidth: CGFloat = 3
        let barInset: CGFloat = 4
        charIndex = 0
        while charIndex < length {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            guard let color = storage.attribute(.blockquoteLeftBorder, at: charIndex, effectiveRange: &effectiveRange) as? NSColor,
                  effectiveRange.location != NSNotFound else {
                charIndex = effectiveRange.location != NSNotFound ? effectiveRange.location + effectiveRange.length : charIndex + 1
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
            var lineStart = glyphRange.location
            let glyphEnd = glyphRange.location + glyphRange.length

            while lineStart < glyphEnd {
                var lineGlyphRange = NSRange(location: NSNotFound, length: 0)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineStart, effectiveRange: &lineGlyphRange, withoutAdditionalLayout: true)
                guard lineGlyphRange.location != NSNotFound else { break }

                let bandHeight = lineRect.height
                guard bandHeight > 0 else {
                    lineStart = lineGlyphRange.location + lineGlyphRange.length
                    continue
                }

                let barRect = NSRect(
                    x: insetX + barInset,
                    y: lineRect.origin.y + insetY,
                    width: barWidth,
                    height: bandHeight
                )
                if barRect.intersects(rect) {
                    color.withAlphaComponent(0.75).setFill()
                    let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
                    path.fill()
                }
                lineStart = lineGlyphRange.location + lineGlyphRange.length
            }
            charIndex = effectiveRange.location + effectiveRange.length
        }
    }

    override func mouseDown(with event: NSEvent) {
        if activatePaneOnReadOnlyInteraction(isEditable: isEditable, onActivatePane: onActivatePane) {
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        if let hit = taskCheckboxTarget(at: point) {
            _ = toggleTaskCheckbox(atCharacterIndex: hit.markerRange.location)
            return
        }

        // Check if clicking on an image markdown
        if let embedID = imageEmbedTarget(at: point) {
            onSelectEmbed?(embedID)
            return
        }

        if let target = wikilinkTarget(at: point) {
            if wikilinkMarkdownIsHidden(at: point) {
                let openInNewTab = event.modifierFlags.contains(.command)
                _ = handleLinkClick(target, openInNewTab: openInNewTab)
                return
            }
            // Markdown is exposed (always-on markdown mode, or the caret's active
            // block under hide-while-typing): fall through so the click places the
            // caret for editing instead of navigating.
        }

        // Check if clicking on a tag
        if let tag = tagTarget(at: point) {
            let openInNewTab = event.modifierFlags.contains(.command)
            _ = handleTagClick(tag, openInNewTab: openInNewTab)
            return
        }
        super.mouseDown(with: event)
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let oldTrackingArea = trackingArea {
            removeTrackingArea(oldTrackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if hovering over an interactive element
        if taskCheckboxTarget(at: point) != nil ||
           imageEmbedTarget(at: point) != nil ||
           wikilinkTarget(at: point) != nil ||
           tagTarget(at: point) != nil ||
           urlTarget(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    func imageEmbedTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        // Check if this character is part of an image markdown
        let nsText = string as NSString
        let textRange = NSRange(location: 0, length: nsText.length)

        guard let regex = Self.inlineImageRegex else { return nil }
        let matches = regex.matches(in: string, range: textRange)

        for match in matches {
            let matchRange = match.range(at: 0)
            if NSLocationInRange(charIndex, matchRange) {
                let source = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(matchRange.location)-\(source)"
            }
        }

        return nil
    }

    func wikilinkTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.wikilinkTarget, at: charIndex, effectiveRange: nil) as? String
    }

    /// Whether the `[[...]]` markdown for the link at `viewPoint` is currently hidden,
    /// which is the only case a WikiLink click should navigate. The markdown is hidden
    /// only when hide-while-typing is on AND the click lands outside the caret's block
    /// (the caret's block is revealed/exposed). In always-on markdown mode the syntax is
    /// visible everywhere, so this returns false and clicks never navigate.
    func wikilinkMarkdownIsHidden(at viewPoint: NSPoint) -> Bool {
        guard settings?.hideMarkdownWhileEditing == true else { return false }
        guard let layout = layoutManager, let container = textContainer else { return true }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )

        // The caret's block has its markdown revealed; every other block is collapsed.
        // No active block (read-only / unfocused pane) ⇒ all links collapsed ⇒ clickable.
        let reveal = MarkdownPreviewBlockReveal.make(
            from: textStorage?.string ?? string,
            cursorLocation: selectedRange().location,
            isEditable: isEditable
        )
        guard let blockRange = reveal.blockRange else { return true }
        return !NSLocationInRange(charIndex, blockRange)
    }

    func tagTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.tagTarget, at: charIndex, effectiveRange: nil) as? String
    }

    func urlTarget(at viewPoint: NSPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.link, at: charIndex, effectiveRange: nil) as? URL
    }

    // MARK: - Focus support

    private var focusObserver: Any?

    func installFocusObserver() {
        guard focusObserver == nil else { return }
        focusObserver = NotificationCenter.default.addObserver(
            forName: .focusEditor,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isEditable else { return }
            preserveScrollOffset(for: self) {
                self.window?.makeFirstResponder(self)
            }
        }
    }

    private var saveCursorObserver: Any?

    func installSaveCursorObserver(appState: AppState) {
        guard saveCursorObserver == nil else { return }
        saveCursorObserver = NotificationCenter.default.addObserver(
            forName: .saveCursorPosition,
            object: nil,
            queue: .main
        ) { [weak self, weak appState] _ in
            guard let self, self.isEditable, let appState else { return }
            appState.pendingCursorRange = self.selectedRange()
            appState.pendingScrollOffsetY = self.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        }
    }

    // MARK: - CMD-K observer

    private var commandKObserver: Any?

    func installCommandKObserver() {
        guard commandKObserver == nil else { return }
        commandKObserver = NotificationCenter.default.addObserver(
            forName: .commandKPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isEditable else {
                self?.onCommandPaletteFallback?()
                return
            }
            let sel = self.selectedRange()
            if sel.length > 0,
               let selectedText = (self.string as NSString?)?.substring(with: sel),
               !selectedText.isEmpty {
                self.pendingWikilinkAlias = selectedText
                self.pendingWikilinkSelectionRange = sel
                self.onWikiLinkRequest?()
            } else {
                self.onCommandPaletteFallback?()
            }
        }
    }

    // MARK: - Search highlight support

    private var searchObserver: Any?
    private var searchClearObserver: Any?
    private var replaceCurrentObserver: Any?
    private var replaceAllObserver: Any?
    var lastSearchHighlightRanges: [NSRange] = []
    var lastSearchFocusIndex: Int = -1
    /// Caret-move reveal memo: caches the parsed document per text version and the
    /// block range currently revealed under the caret, so the synchronous reveal
    /// passes skip redundant parsing while the caret stays within one block.
    /// `noteTextChanged()` is bumped on every character edit (Coordinator's
    /// didProcessEditing and setPlainText), which invalidates both caches.
    var previewRevealMemo = MarkdownPreviewRevealMemo()

    /// Clears the revealed-block gate so the next revealCurrentBlockMarkdownAtCursor()
    /// recomputes. Used after a full re-hide sweep that invalidated the visible reveal.
    func invalidateRevealedBlock() {
        previewRevealMemo.invalidateRevealedBlock()
    }

    func installSearchObservers() {
        guard searchObserver == nil else { return }
        searchObserver = NotificationCenter.default.addObserver(
            forName: .scrollToSearchMatch,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let query = note.userInfo?[SearchMatchKey.query] as? String,
                  let focusIndex = note.userInfo?[SearchMatchKey.matchIndex] as? Int else { return }
            self.applySearchHighlights(query: query, focusIndex: focusIndex)
        }
        searchClearObserver = NotificationCenter.default.addObserver(
            forName: .clearSearchHighlights,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSearchHighlights()
        }
        replaceCurrentObserver = NotificationCenter.default.addObserver(
            forName: .replaceCurrentMatch,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.participatesInGlobalSearch, self.isEditable,
                  let query = note.userInfo?[SearchMatchKey.query] as? String,
                  let focusIndex = note.userInfo?[SearchMatchKey.matchIndex] as? Int,
                  let replacement = note.userInfo?[SearchMatchKey.replacement] as? String else { return }
            let advanceAfter = (note.userInfo?[SearchMatchKey.advanceAfter] as? Bool) ?? false
            self.replaceCurrentMatch(query: query, focusIndex: focusIndex, replacement: replacement, advanceAfter: advanceAfter)
        }
        replaceAllObserver = NotificationCenter.default.addObserver(
            forName: .replaceAllMatches,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.participatesInGlobalSearch, self.isEditable,
                  let query = note.userInfo?[SearchMatchKey.query] as? String,
                  let replacement = note.userInfo?[SearchMatchKey.replacement] as? String else { return }
            self.replaceAllMatches(query: query, replacement: replacement)
        }
    }

    private func applySearchHighlights(query: String, focusIndex: Int) {
        guard let storage = textStorage, !query.isEmpty else {
            clearSearchHighlights()
            return
        }
        let content = storage.string
        let needle = query.lowercased()
        var matches: [NSRange] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(of: needle, options: .caseInsensitive, range: searchStart..<content.endIndex) {
            matches.append(NSRange(range, in: content))
            searchStart = range.upperBound
            if matches.count > 2000 { break }
        }

        let dimHighlight = NSColor.yellow.withAlphaComponent(0.30)
        let focusHighlight = NSColor.yellow
        storage.beginEditing()
        let storageLength = storage.length
        for range in lastSearchHighlightRanges {
            // Ranges may be stale relative to the current storage (e.g. after an
            // external edit). Skip any that no longer fit so removeAttribute can't
            // throw NSRangeException and abort the rest of the highlight update.
            guard NSMaxRange(range) <= storageLength else { continue }
            storage.removeAttribute(.backgroundColor, range: range)
        }
        for (i, range) in matches.enumerated() {
            if i == focusIndex {
                storage.addAttribute(.backgroundColor, value: focusHighlight, range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            } else {
                storage.addAttribute(.backgroundColor, value: dimHighlight, range: range)
            }
        }
        storage.endEditing()
        lastSearchHighlightRanges = matches
        lastSearchFocusIndex = focusIndex

        // Report match count back to SwiftUI
        onMatchCountUpdate?(matches.count)

        // Scroll focused match into view (don't select — selection rendering overwrites highlight attributes)
        if matches.indices.contains(focusIndex) {
            scrollRangeToVisible(matches[focusIndex])
        }
    }

    private func clearSearchHighlights() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        let storageLength = storage.length
        for range in lastSearchHighlightRanges {
            guard NSMaxRange(range) <= storageLength else { continue }
            storage.removeAttribute(.backgroundColor, range: range)
        }
        storage.endEditing()
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
        applyMarkdownStyling()
    }

    private func replaceCurrentMatch(query: String, focusIndex: Int, replacement: String, advanceAfter: Bool) {
        guard !query.isEmpty,
              lastSearchHighlightRanges.indices.contains(focusIndex) else { return }
        let range = lastSearchHighlightRanges[focusIndex]
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()

        // Recompute matches against new text. Anchor on the position of the replacement
        // so the next focused match is the one that was after the replaced range.
        let newCaret = range.location + (replacement as NSString).length
        let newFocus: Int
        if advanceAfter {
            newFocus = nextMatchIndex(forQuery: query, after: newCaret)
        } else {
            newFocus = nextMatchIndex(forQuery: query, after: range.location)
        }
        applySearchHighlights(query: query, focusIndex: newFocus)
    }

    private func replaceAllMatches(query: String, replacement: String) {
        guard !query.isEmpty, let storage = textStorage else { return }
        let content = storage.string
        // Use Foundation's single-pass replace instead of collecting every match range.
        // A note can contain millions of occurrences of a short query; materializing
        // `[NSRange]` for each would spike memory and freeze the main thread.
        let mutable = NSMutableString(string: content)
        let initialSearchRange = NSRange(location: 0, length: (mutable as NSString).length)
        let replacedCount = mutable.replaceOccurrences(
            of: query,
            with: replacement,
            options: .caseInsensitive,
            range: initialSearchRange
        )
        let resultString = mutable as String

        guard replacedCount > 0 else {
            applySearchHighlights(query: query, focusIndex: 0)
            return
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        guard shouldChangeText(in: fullRange, replacementString: resultString) else { return }
        // Highlight ranges are about to be invalidated by the full-document replace.
        // Drop them now so the debounced restyle (which re-applies highlights via
        // reapplySearchHighlights) can't read out-of-bounds NSRanges and crash.
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
        storage.replaceCharacters(in: fullRange, with: resultString)
        didChangeText()

        applySearchHighlights(query: query, focusIndex: 0)
    }

    /// Returns the index of the first match whose range starts at or after `location`,
    /// wrapping to 0 if none. Recomputes matches against the live text storage.
    private func nextMatchIndex(forQuery query: String, after location: Int) -> Int {
        guard let storage = textStorage else { return 0 }
        let content = storage.string
        var matches: [NSRange] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let r = content.range(of: query, options: .caseInsensitive, range: searchStart..<content.endIndex) {
            matches.append(NSRange(r, in: content))
            searchStart = r.upperBound
            if matches.count > 2000 { break }
        }
        if matches.isEmpty { return 0 }
        if let idx = matches.firstIndex(where: { $0.location >= location }) {
            return idx
        }
        return 0
    }

    func reapplySearchHighlights() {
        guard !lastSearchHighlightRanges.isEmpty, let storage = textStorage else { return }
        let dimHighlight = NSColor.yellow.withAlphaComponent(0.30)
        let focusHighlight = NSColor.yellow
        storage.beginEditing()
        let storageLength = storage.length
        for (i, range) in lastSearchHighlightRanges.enumerated() {
            guard NSMaxRange(range) <= storageLength else { continue }
            if i == lastSearchFocusIndex {
                storage.addAttribute(.backgroundColor, value: focusHighlight, range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            } else {
                storage.addAttribute(.backgroundColor, value: dimHighlight, range: range)
            }
        }
        storage.endEditing()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
            self?.refreshCollapsibleToggles()
            self?.refreshCodeBlockCopyButtons()
            self?.refreshAISparkle()
        }
    }

    // MARK: - Block indent / dedent

    private static let indentString = "    " // 4 spaces

    /// Tab with a multi-line selection → indent every selected line.
    /// Tab with a cursor or single-line selection → insert a literal tab (default).
    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let nsText = string as NSString

        // Determine whether the selection spans more than one line.
        let selText = sel.length > 0 ? nsText.substring(with: sel) : ""
        let spansMultipleLines = selText.contains("\n")

        guard spansMultipleLines else {
            super.insertTab(sender)
            return
        }

        indentSelectedLines(dedent: false)
    }

    /// Shift-Tab: dedent every line touched by the selection.
    /// Intercept via keyDown so we catch the Shift modifier.
    private func indentSelectedLines(dedent: Bool) {
        guard let storage = textStorage else { return }
        let nsText = string as NSString
        let sel = selectedRange()

        // Expand selection to cover full lines.
        let linesRange = nsText.lineRange(for: sel)

        let linesText = nsText.substring(with: linesRange)
        var lines = linesText.components(separatedBy: "\n")

        // The last component after the trailing newline is always an empty
        // string artifact — keep it so we don't drop the terminating newline.
        let indent = Self.indentString

        var newLines: [String] = []
        for (i, line) in lines.enumerated() {
            // Don't modify the empty artifact at the end.
            if i == lines.count - 1 && line.isEmpty {
                newLines.append(line)
                continue
            }
            if dedent {
                if line.hasPrefix(indent) {
                    newLines.append(String(line.dropFirst(indent.count)))
                } else if line.hasPrefix("\t") {
                    newLines.append(String(line.dropFirst(1)))
                } else {
                    newLines.append(line) // nothing to dedent
                }
            } else {
                newLines.append(indent + line)
            }
        }

        let newText = newLines.joined(separator: "\n")
        if shouldChangeText(in: linesRange, replacementString: newText) {
            storage.beginEditing()
            storage.replaceCharacters(in: linesRange, with: newText)
            storage.endEditing()
            didChangeText()

            // Restore a selection that covers the same lines.
            let newLinesRange = NSRange(location: linesRange.location, length: (newText as NSString).length)
            setSelectedRange(newLinesRange)
        }
    }

    override func insertNewline(_ sender: Any?) {
        // Preserve the leading whitespace of the current line on the new line,
        // and continue bullet lists (- or *) automatically.
        let cursor = selectedRange().location
        let nsText = string as NSString
        guard cursor != NSNotFound else { super.insertNewline(sender); return }

        // Find the start of the current line.
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let lineText = nsText.substring(with: lineRange)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        // Measure leading whitespace.
        var indentEnd = lineText.startIndex
        for ch in lineText {
            if ch == " " || ch == "\t" { indentEnd = lineText.index(after: indentEnd) }
            else { break }
        }
        let indent = String(lineText[lineText.startIndex..<indentEnd])
        let afterIndent = String(lineText[indentEnd...])

        // Detect bullet marker: "- " or "* " (unordered list items).
        // Also handle "- [ ] " and "- [x] " task list items.
        let bulletMarkers = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] ", "- ", "* "]
        var detectedMarker: String? = nil
        for marker in bulletMarkers {
            if afterIndent.hasPrefix(marker) {
                detectedMarker = marker
                break
            }
        }

        // Detect ordered list: "1. ", "2. ", etc.
        if detectedMarker == nil {
            let orderedRegex = try? NSRegularExpression(pattern: #"^(\d+)\. "#)
            let afterIndentNS = afterIndent as NSString
            if let match = orderedRegex?.firstMatch(in: afterIndent, range: NSRange(location: 0, length: afterIndentNS.length)) {
                let numberRange = match.range(at: 1)
                let currentNumber = Int(afterIndentNS.substring(with: numberRange)) ?? 1
                let markerLength = match.range(at: 0).length
                let itemContent = String(afterIndent.dropFirst(markerLength))

                if itemContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty ordered item — remove it and break out of the list.
                    let deletionRange = NSRange(location: lineRange.location, length: cursor - lineRange.location)
                    if shouldChangeText(in: deletionRange, replacementString: "") {
                        replaceCharacters(in: deletionRange, with: "")
                        didChangeText()
                    }
                    super.insertNewline(sender)
                    return
                }

                super.insertNewline(sender)
                insertText(indent + "\(currentNumber + 1). ", replacementRange: selectedRange())
                return
            }
        }

        guard let marker = detectedMarker else {
            // No bullet — just continue with indent as before.
            super.insertNewline(sender)
            if !indent.isEmpty { insertText(indent, replacementRange: selectedRange()) }
            return
        }

        let bulletContent = String(afterIndent.dropFirst(marker.count))

        // If the bullet line is empty (user pressed enter on a blank bullet),
        // remove the bullet and insert a plain newline instead.
        if bulletContent.trimmingCharacters(in: .whitespaces).isEmpty {
            // Delete back to the start of the bullet line and insert a bare newline.
            let deletionRange = NSRange(location: lineRange.location, length: cursor - lineRange.location)
            if shouldChangeText(in: deletionRange, replacementString: "") {
                replaceCharacters(in: deletionRange, with: "")
                didChangeText()
            }
            super.insertNewline(sender)
            return
        }

        // Otherwise continue the list: new line with same indent + same marker.
        // For task items, always start unchecked.
        let continuationMarker: String
        if marker.hasPrefix("- [") || marker.hasPrefix("* [") {
            let bulletChar = marker.hasPrefix("-") ? "-" : "*"
            continuationMarker = "\(bulletChar) [ ] "
        } else {
            continuationMarker = marker
        }

        super.insertNewline(sender)
        insertText(indent + continuationMarker, replacementRange: selectedRange())
    }

    override func keyDown(with event: NSEvent) {
        // ⌥J opens the inline AI bar at the cursor/selection (same as clicking the ✨).
        // Works even when the ✨ is hidden via Settings.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .option, event.charactersIgnoringModifiers?.lowercased() == "j" {
            aiSparkleTapped()
            return
        }
        if let popover = completionPopover, popover.isShown {
            switch event.keyCode {
            case KeyCode.downArrow: completionVC?.moveSelection(by: 1);    return
            case KeyCode.upArrow: completionVC?.moveSelection(by: -1);     return
            case KeyCode.returnKey, KeyCode.numpadEnter: completionVC?.selectCurrentItem(); return
            case KeyCode.escape: dismissCompletion();                      return
            default: break
            }
        }
        // Shift-Tab on a multi-line selection → dedent.
        if event.keyCode == KeyCode.tab, event.modifierFlags.contains(.shift) {
            let sel = selectedRange()
            let selText = sel.length > 0 ? (string as NSString).substring(with: sel) : ""
            if selText.contains("\n") {
                indentSelectedLines(dedent: true)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            // Only intercept paste when this text view (or one of its descendants) is the first responder.
            // If focus is on a terminal or browser pane, let the event pass through naturally.
            let responder = window?.firstResponder
            let isSelfFocused: Bool
            if let view = responder as? NSView {
                isSelfFocused = view === self || view.isDescendant(of: self)
            } else {
                isSelfFocused = responder === self
            }
            guard isSelfFocused else { return false }
            paste(self)
            return true
        }
        // CMD-K with a non-empty selection: open the wikilink picker and use the
        // selected text as the alias, so the result is [[picked-note|selected text]].
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            let sel = selectedRange()
            if sel.length > 0, let selectedText = (string as NSString?)?.substring(with: sel), !selectedText.isEmpty {
                pendingWikilinkAlias = selectedText
                pendingWikilinkSelectionRange = sel
                onWikiLinkRequest?()
                return true
            }
        }
        // CMD-Shift-K: delete the active line.
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "k" {
            let cursor = selectedRange().location
            guard cursor != NSNotFound else { return false }
            let nsText = string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            var deletionRange = lineRange
            var cursorPos = lineRange.location
            if lineRange.length > 0 {
                let lastChar = nsText.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1))
                if lastChar != "\n" && lastChar != "\r\n" && lineRange.location > 0 {
                    deletionRange = NSRange(location: lineRange.location - 1, length: lineRange.length + 1)
                    cursorPos = lineRange.location - 1
                }
            }
            if shouldChangeText(in: deletionRange, replacementString: "") {
                replaceCharacters(in: deletionRange, with: "")
                didChangeText()
                setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func prettifyTableIfNeeded() {
        guard isEditable, !isPrettifyingTable else { return }
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return }

        let source = string
        let parser = MarkdownDocumentParser()
        let document = parser.parse(source)

        // Only prettify when cursor is OUTSIDE all tables
        let cursorInTable = document.blocks.contains {
            guard case .table = $0.kind else { return false }
            return NSLocationInRange(cursor, $0.range)
        }
        guard !cursorInTable else { return }

        let nsSource = source as NSString
        isPrettifyingTable = true
        defer { isPrettifyingTable = false }

        // Prettify all tables in the document
        let tableBlocks = document.blocks.filter { if case .table = $0.kind { return true }; return false }
        // Process in reverse so earlier ranges stay valid after replacements
        for tableBlock in tableBlocks.reversed() {
            let tableText = nsSource.substring(with: tableBlock.range)
            guard let result = MarkdownTablePrettifier.prettify(
                tableText: tableText,
                cursorOffsetInTable: 0
            ) else { continue }
            guard result.formatted != tableText else { continue }

            if shouldChangeText(in: tableBlock.range, replacementString: result.formatted) {
                replaceCharacters(in: tableBlock.range, with: result.formatted)
                didChangeText()
            }
        }
    }

    func expandSlashCommandIfNeeded() {
        let cursor = selectedRange().location
        guard cursor != NSNotFound,
              let context = slashCommandContext(in: string, cursor: cursor),
              let command = SlashCommand(rawValue: context.query) else { return }

        let output = resolveSlashCommandOutput(
            command,
            context: SlashCommandResolverContext(
                now: slashCommandNowProvider(),
                currentFileURL: currentFileURL,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: slashCommandTimeZone
            )
        )
        guard shouldChangeText(in: context.range, replacementString: output) else { return }
        replaceCharacters(in: context.range, with: output)
        didChangeText()
        setSelectedRange(NSRange(location: context.range.location + (output as NSString).length, length: 0))
    }

    func checkForLinkTrigger(plainText: String? = nil, cursor cursorOverride: Int? = nil) {
        let text = plainText ?? string
        let nsText = text as NSString
        var cursor = cursorOverride ?? selectedRange().location
        guard cursor != NSNotFound else { dismissCompletion(); return }
        cursor = min(max(0, cursor), nsText.length)
        guard cursor > 0 else { dismissCompletion(); return }

        // Some NSTextView edit notifications report cursor after a trailing paragraph newline.
        while cursor > 0 {
            let ch = nsText.substring(with: NSRange(location: cursor - 1, length: 1))
            if ch.rangeOfCharacter(from: .newlines) != nil { cursor -= 1 } else { break }
        }

        let startOffset = max(0, cursor - 400)
        let searchRange = NSRange(location: startOffset, length: cursor - startOffset)
        let sub = nsText.substring(with: searchRange) as NSString
        let bracketRange = sub.range(of: "[[", options: .backwards)
        if bracketRange.location != NSNotFound {
            let absStart = startOffset + bracketRange.location
            let tokenRange = NSRange(location: absStart, length: cursor - absStart)
            let token = nsText.substring(with: tokenRange)
            guard token.hasPrefix("[[") else { dismissCompletion(); return }
            let query = String(token.dropFirst(2))
                .trimmingCharacters(in: .newlines)
                .trimmingCharacters(in: .whitespaces)
            debugLog("query='\(query)' allFiles=\(allFiles.count)")
            // Limit completion to the actively typed token only.
            if !query.contains("]]") && query.count <= 120 {
                linkTypingRange = tokenRange
                // Don't re-open the picker if the user ESC'd it for this [[ token.
                if wikilinkPickerSuppressed { return }
                // Use command palette for wiki link picker instead of completion popover
                onWikiLinkRequest?()
                return
            }
        }
        dismissCompletion()
    }

    func dismissCompletion() {
        completionPopover?.close()
        completionPopover = nil
        completionVC = nil
        linkTypingRange = nil
        wikilinkPickerSuppressed = false
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    func insertLink(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let alias = pendingWikilinkAlias
        let aliasRange = pendingWikilinkSelectionRange
        clearPendingWikilinkInsertion()

        if linkTypingRange == nil, let alias, !alias.isEmpty {
            // CMD-K with selected text: replace the selection with [[name|alias]].
            let currentLength = (string as NSString).length
            let selRange = aliasRange ?? selectedRange()
            guard selRange.location != NSNotFound,
                  selRange.location + selRange.length <= currentLength else { return }
            let linkText = "[[\(name)|\(alias)]]"
            if shouldChangeText(in: selRange, replacementString: linkText) {
                replaceCharacters(in: selRange, with: linkText)
                didChangeText()
                let afterLink = selRange.location + (linkText as NSString).length
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.window?.makeFirstResponder(self)
                    self.setSelectedRange(NSRange(location: afterLink, length: 0))
                }
            }
            return
        }

        // Normal [[...]] typing flow.
        guard let range = linkTypingRange else { return }
        guard range.location >= 0, range.location + range.length <= (string as NSString).length else {
            dismissCompletion()
            return
        }
        let typed = (string as NSString).substring(with: range)
        guard typed.hasPrefix("[["), !typed.contains("\n"), range.length <= 120 else {
            dismissCompletion()
            return
        }
        let linkText = "[[\(name)]]"
        if shouldChangeText(in: range, replacementString: linkText) {
            replaceCharacters(in: range, with: linkText)
            didChangeText()
            // Restore focus and place cursor after ]] once the palette has dismissed.
            let afterLink = range.location + (linkText as NSString).length
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
                self.setSelectedRange(NSRange(location: afterLink, length: 0))
            }
        }
        dismissCompletion()
    }

    func handleLinkClick(_ link: Any, openInNewTab: Bool) -> Bool {
        if let url = link as? URL {
            // Use injected callback if available, otherwise fall back to NSWorkspace
            if let onOpenExternalURL = onOpenExternalURL {
                onOpenExternalURL(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            return true
        }

        guard let inner = link as? String else { return false }
        // Strip alias and heading for resolution
        let name = inner.components(separatedBy: "|").first
            .flatMap { $0.components(separatedBy: "#").first }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? inner

        if let match = allFiles.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased() }) {
            onOpenFile?(match, openInNewTab)
            return true
        }

        // Unresolved — create a new note with this name in the same folder as the current file.
        onCreateNote?(name, currentFileURL?.deletingLastPathComponent())
        return true
    }

    func handleTagClick(_ tag: String, openInNewTab: Bool) -> Bool {
        guard !tag.isEmpty else { return false }
        onOpenTag?(tag, openInNewTab)
        return true
    }

    func refreshInlineImagePreviews() {
        // Inline image previews disabled - images now only show in sidebar
        // This function is kept for compatibility but does nothing
    }

    // MARK: - Embedded Notes

    func inlineEmbedMatches() -> [InlineEmbedMatch] {
        guard let regex = Self.embedRegex else { return [] }
        let nsText = string as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: string, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            // Extract note name (before any pipe alias or heading anchor)
            let noteName = raw
                .components(separatedBy: "|").first?
                .components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !noteName.isEmpty else { return nil }

            let fullRange = match.range(at: 0)
            let paragraphRange = nsText.paragraphRange(for: fullRange)
            let id = "\(fullRange.location)-\(noteName)"

            // Find the note file
            let normalizedName = noteName.lowercased()
            let noteURL = allFiles.first { url in
                url.deletingPathExtension().lastPathComponent.lowercased() == normalizedName
            }

            // Get content if note exists
            var content: String?
            if let noteURL = noteURL {
                content = try? String(contentsOf: noteURL, encoding: .utf8)
            }

            return InlineEmbedMatch(
                id: id,
                range: fullRange,
                paragraphRange: paragraphRange,
                noteName: noteName,
                content: content,
                noteURL: noteURL
            )
        }
    }

    func inlineImageMatches() -> [InlineImageMatch] {
        guard let regex = Self.inlineImageRegex else { return [] }
        let nsText = string as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: string, range: range).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let caption = nsText.substring(with: match.range(at: 1))
            let source = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRange = match.range(at: 0)
            let paragraphRange = nsText.paragraphRange(for: fullRange)
            return InlineImageMatch(
                id: "\(fullRange.location)-\(source)",
                range: fullRange,
                paragraphRange: paragraphRange,
                source: source,
                caption: caption
            )
        }
    }

    func visibleInlineImageMatches() -> [InlineImageMatch] {
        let matches = inlineImageMatches()
        guard !matches.isEmpty else { return [] }

        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL
        let sections = collapsibleParser.parse(string)
        let collapsedRanges = sections.compactMap { section -> NSRange? in
            guard section.contentRange.length > 0 else { return nil }
            let sectionId = section.getIdentifier()
            return collapsibleStateManager.isCollapsed(sectionId, in: fileURL) ? section.contentRange : nil
        }

        guard !collapsedRanges.isEmpty else { return matches }
        return matches.filter { match in
            !collapsedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
    }

    struct InlinePreviewAsset {
        let image: NSImage
        let imageDataType: NSPasteboard.PasteboardType
        let preservesAnimation: Bool
    }

    func inlinePreviewAsset(fromFileURL url: URL, maxPixelSize: CGFloat) -> InlinePreviewAsset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return inlinePreviewAsset(from: data, maxPixelSize: maxPixelSize)
    }

    func inlinePreviewAsset(from data: Data, maxPixelSize: CGFloat) -> InlinePreviewAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let imageType = (CGImageSourceGetType(source) as String?) ?? "public.image"
        let pasteboardType = NSPasteboard.PasteboardType(imageType)
        let frameCount = CGImageSourceGetCount(source)
        let preservesAnimation = (imageType == "com.compuserve.gif" || imageType == "public.gif") && frameCount > 1

        if preservesAnimation, let image = NSImage(data: data) {
            return InlinePreviewAsset(image: image, imageDataType: pasteboardType, preservesAnimation: true)
        }

        if let image = downsampledImage(from: source, maxPixelSize: maxPixelSize) ?? NSImage(data: data) {
            return InlinePreviewAsset(image: image, imageDataType: pasteboardType, preservesAnimation: false)
        }

        return nil
    }

    private func downsampledImage(from source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(400, Int(maxPixelSize)),
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        return image.size.width > 0 || image.size.height > 0 ? image : nil
    }

    // MARK: - Image paste handling

    /// Handles paste events for images. Saves image to .images folder and inserts markdown.
    override func paste(_ sender: Any?) {
        // Image data takes priority: if the pasteboard carries actual image
        // binary data, save it to .images/ and insert a local Markdown link.
        // This must come before HTML so that copying an image from a browser
        // (which puts both image data AND HTML on the pasteboard) correctly
        // saves the image locally rather than emitting a remote URL.
        if handlePaste(from: .general) {
            return
        }

        // No image data — try converting HTML to Markdown.
        if handleHTMLPaste(from: .general) {
            return
        }

        super.paste(sender)
    }

    @discardableResult
    func handlePaste(from pasteboard: NSPasteboard) -> Bool {
        guard let asset = readPastedImageAsset(from: pasteboard) else {
            return false
        }
        handleImagePaste(asset: asset)
        return true
    }

    private struct PastedImageAsset {
        let image: NSImage
        let originalData: Data?
        let fileExtension: String
    }

    private func readPastedImageAsset(from pasteboard: NSPasteboard) -> PastedImageAsset? {
        let gifTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(rawValue: "com.compuserve.gif"),
            NSPasteboard.PasteboardType(rawValue: "public.gif"),
            NSPasteboard.PasteboardType(rawValue: "GIF"),
            NSPasteboard.PasteboardType(rawValue: "GIFf"),
        ]

        for type in gifTypes {
            if let gifData = pasteboard.data(forType: type),
               let image = NSImage(data: gifData) {
                return PastedImageAsset(image: image, originalData: gifData, fileExtension: "gif")
            }
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let firstURL = fileURLs.first,
           let image = NSImage(contentsOf: firstURL) {
            let ext = firstURL.pathExtension.lowercased()
            if ext == "gif", let data = try? Data(contentsOf: firstURL) {
                return PastedImageAsset(image: image, originalData: data, fileExtension: ext)
            }
            return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
        }

        if let urlData = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url")),
           let urlString = String(data: urlData, encoding: .utf8),
           let url = URL(string: urlString),
           let image = NSImage(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            if ext == "gif", let data = try? Data(contentsOf: url) {
                return PastedImageAsset(image: image, originalData: data, fileExtension: ext)
            }
            return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
        }

        guard let image = readImage(from: pasteboard) else { return nil }
        return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
    }

    /// Reads an image from the pasteboard using various methods
    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let firstImage = images.first {
            return firstImage
        }

        if NSImage.canInit(with: pasteboard) {
            if let image = NSImage(pasteboard: pasteboard) {
                return image
            }
        }

        let tiffTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            NSPasteboard.PasteboardType(rawValue: "public.tiff"),
            NSPasteboard.PasteboardType(rawValue: "TIFF"),
            NSPasteboard.PasteboardType(rawValue: "com.apple.tiff"),
            NSPasteboard.PasteboardType(rawValue: "NeXT TIFF v4.0 pasteboard type"),
        ]

        for type in tiffTypes {
            if let tiffData = pasteboard.data(forType: type) {
                if let image = NSImage(data: tiffData) {
                    return image
                }
            }
        }

        let pngTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType(rawValue: "public.png"),
            NSPasteboard.PasteboardType(rawValue: "PNG"),
            NSPasteboard.PasteboardType(rawValue: "PNGf"),
            NSPasteboard.PasteboardType(rawValue: "Apple PNG pasteboard type"),
        ]

        for type in pngTypes {
            if let pngData = pasteboard.data(forType: type) {
                if let image = NSImage(data: pngData) {
                    return image
                }
            }
        }

        let otherImageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(rawValue: "public.jpeg"),
            NSPasteboard.PasteboardType(rawValue: "public.jpg"),
            NSPasteboard.PasteboardType(rawValue: "JPEG"),
            NSPasteboard.PasteboardType(rawValue: "JFIF"),
            NSPasteboard.PasteboardType(rawValue: "public.image"),
            NSPasteboard.PasteboardType(rawValue: "com.apple.pict"),
            NSPasteboard.PasteboardType(rawValue: "GIF"),
            NSPasteboard.PasteboardType(rawValue: "GIFf"),
            NSPasteboard.PasteboardType(rawValue: "BMP"),
            NSPasteboard.PasteboardType(rawValue: "BMPf"),
        ]

        for type in otherImageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    private func handleImagePaste(asset: PastedImageAsset) {
        guard let currentFileURL = currentFileURL else {
            // No current file, fall back to regular paste (but images can't be pasted without a file context)
            return
        }

        let fileFolder = currentFileURL.deletingLastPathComponent()
        let imagesFolder = fileFolder.appendingPathComponent(".images")

        // Create .images folder if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imagesFolder.path) {
            do {
                try fileManager.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            } catch {
                debugLog("Failed to create .images folder: \(error)")
                return
            }
        }

        // Generate unique filename with timestamp and random component
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)
        let filename = "image_\(timestamp)_\(random).\(asset.fileExtension)"
        let imagePath = imagesFolder.appendingPathComponent(filename)

        let dataToWrite: Data
        if let originalData = asset.originalData {
            dataToWrite = originalData
        } else {
            guard let tiffData = asset.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                debugLog("Failed to convert image to PNG")
                return
            }
            dataToWrite = pngData
        }

        do {
            try dataToWrite.write(to: imagePath)
        } catch {
            debugLog("Failed to save image: \(error)")
            return
        }

        // Calculate relative path from current file to image
        let relativePath = ".images/\(filename)"
        let markdown = "![](\(relativePath))"

        // Insert markdown at current cursor position
        let currentRange = selectedRange()
        if shouldChangeText(in: currentRange, replacementString: markdown) {
            replaceCharacters(in: currentRange, with: markdown)
            didChangeText()
        }
    }

    // MARK: - HTML to Markdown Conversion

    /// Returns true when the insertion point is inside (or on the opening line
    /// of) a fenced code block, so HTML paste should be left as-is.
    private func cursorIsInCodeBlock() -> Bool {
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return false }
        let nsText = string as NSString
        let len = nsText.length

        // Pattern: opening ``` fence at the start of a line.
        guard let fenceRegex = try? NSRegularExpression(
            pattern: "^[ \\t]{0,3}```",
            options: [.anchorsMatchLines]
        ) else { return false }

        let fenceMatches = fenceRegex.matches(in: string, options: [],
                                              range: NSRange(location: 0, length: len))

        // Walk fence matches in pairs; an unpaired opening also counts.
        var i = 0
        while i < fenceMatches.count {
            let open = fenceMatches[i]
            let openEnd = open.range.location + open.range.length

            if i + 1 < fenceMatches.count {
                let close = fenceMatches[i + 1]
                let closeStart = close.range.location
                // Cursor is inside a complete block.
                if cursor >= open.range.location && cursor <= NSMaxRange(close.range) {
                    return true
                }
                i += 2
            } else {
                // Unpaired opening fence — cursor anywhere from the ``` to end of doc.
                if cursor >= open.range.location {
                    return true
                }
                i += 1
            }
        }
        return false
    }

    /// Converts HTML pasteboard content to Markdown and inserts it.
    /// Checks dedicated HTML pasteboard types first, then falls back to
    /// checking whether the plain-text payload looks like HTML (e.g. when
    /// copying raw HTML source from a text editor or terminal).
    @discardableResult
    func handleHTMLPaste(from pasteboard: NSPasteboard) -> Bool {
        // Never convert when the cursor is inside a fenced code block.
        guard !cursorIsInCodeBlock() else { return false }

        // 1. Try dedicated HTML pasteboard types (browser copies, rich-text apps).
        let htmlTypes: [NSPasteboard.PasteboardType] = [
            .html,
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("Apple HTML pasteboard type"),
            NSPasteboard.PasteboardType("NSHTMLPboardType"),
        ]

        var htmlString: String? = nil
        for type in htmlTypes {
            if let str = pasteboard.string(forType: type) {
                htmlString = str
                break
            }
        }

        // 2. Fallback: plain-text that looks like HTML (raw source pasted from
        //    a terminal, VS Code, etc.). Require at least one structural tag so
        //    we don't accidentally convert markdown or code that uses < >.
        if htmlString == nil, let plain = pasteboard.string(forType: .string) {
            if looksLikeHTML(plain) {
                htmlString = plain
            }
        }

        guard let html = htmlString, !html.isEmpty else {
            return false
        }

        #if DEBUG
        print("[HTML Paste] Source: \(html.prefix(300))")
        #endif

        let markdown = HTMLToMarkdownConverter.convert(html)

        #if DEBUG
        print("[HTML Paste] Result: \(markdown.prefix(300))")
        #endif

        let currentRange = selectedRange()
        guard shouldChangeText(in: currentRange, replacementString: markdown) else {
            return false
        }
        replaceCharacters(in: currentRange, with: markdown)
        didChangeText()
        return true
    }

    /// Returns true if the string contains at least one structural HTML tag
    /// that makes it worth attempting conversion.
    private func looksLikeHTML(_ text: String) -> Bool {
        let structural = ["<ul", "<ol", "<li", "<p>", "<p ", "<h1", "<h2",
                          "<h3", "<h4", "<h5", "<h6", "<table", "<div",
                          "<blockquote", "<pre", "<code"]
        let lower = text.lowercased()
        return structural.contains { lower.contains($0) }
    }
}
