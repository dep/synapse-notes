import Foundation

/// Per-editing-session memo that lets the synchronous caret-move reveal passes
/// (`revealCurrentBlockMarkdownAtCursor` / `revealSemanticInlineMarkdownAtCursor`)
/// skip redundant work. Selection changes fire 1–2 times per keystroke and each
/// reveal previously re-parsed the entire document; this memo caches the parse per
/// text version and gates the block reveal while the caret stays within one block.
/// Pure value type — the owning view bumps `noteTextChanged()` on character edits.
struct MarkdownPreviewRevealMemo {
    /// Monotonic content version, bumped by the owner on every character edit.
    private(set) var textVersion = 0
    /// Number of real parses performed — exposed so tests can assert that repeated
    /// lookups within one text version do no redundant parsing work.
    private(set) var parseCount = 0

    private var cachedDocument: MarkdownDocument?
    private var cachedDocumentVersion = -1
    private var cachedDocumentLength = -1

    /// The parsed block range whose markdown is currently revealed under the caret
    /// (nil when no block is revealed). Recorded together with the text version it
    /// was computed against so text edits implicitly invalidate it.
    private(set) var revealedBlockRange: NSRange?
    private var revealedBlockVersion = -1

    mutating func noteTextChanged() {
        textVersion &+= 1
    }

    /// Clears the revealed-block gate so the next block reveal recomputes. Used after
    /// a full re-hide sweep that invalidated the visible reveal.
    mutating func invalidateRevealedBlock() {
        revealedBlockRange = nil
    }

    mutating func noteRevealedBlock(_ range: NSRange?) {
        revealedBlockRange = range
        revealedBlockVersion = textVersion
    }

    /// True when the block reveal pass has nothing to do: the text is unchanged since
    /// the last reveal and the caret is still inside the block revealed then. A caret
    /// exactly at the block's end boundary counts as inside, matching the containment
    /// rule in `MarkdownPreviewBlockReveal.make`.
    func canSkipBlockReveal(cursorLocation: Int) -> Bool {
        guard revealedBlockVersion == textVersion, let range = revealedBlockRange else { return false }
        return cursorLocation >= range.location && cursorLocation <= range.location + range.length
    }

    /// Returns the parsed document for `source`, re-parsing only when the text version
    /// (or, defensively, the content length) changed since the cached parse.
    mutating func document(for source: String, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownDocument {
        let length = (source as NSString).length
        if let cached = cachedDocument, cachedDocumentVersion == textVersion, cachedDocumentLength == length {
            return cached
        }
        let parsed = parser.parse(source)
        cachedDocument = parsed
        cachedDocumentVersion = textVersion
        cachedDocumentLength = length
        parseCount += 1
        return parsed
    }
}
