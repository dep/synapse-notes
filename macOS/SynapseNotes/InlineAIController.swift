import AppKit
import Combine

/// Orchestrates an inline AI editing session against an NSTextStorage.
///
/// Generate mode: streamed deltas are inserted at the cursor (plain text).
/// Rewrite mode: the original selection is kept; new text streams in after it.
/// On `accept`, the original is deleted and the new text remains. On `reject`,
/// the new text is removed and the original stays. Diff *coloring* is applied
/// by the view layer via the published `originalRange`/`newRange`; this controller
/// owns only the text mutations so the logic stays unit-testable.
final class InlineAIController: ObservableObject {
    enum Mode: Equatable { case idle, generate, rewrite }

    @Published private(set) var mode: Mode = .idle
    /// Range of the original (struck-through) text during a rewrite; nil otherwise.
    @Published private(set) var originalRange: NSRange?
    /// Range of the streamed new text (generate: the inserted text; rewrite: the green text).
    @Published private(set) var newRange: NSRange?

    private weak var storage: NSTextStorage?

    /// Optional edit hook supplied by the view layer. When set, all text mutations are
    /// routed through it (so the host can register undo via shouldChangeText/didChangeText);
    /// when nil, mutations apply directly to the storage (used by unit tests). The closure
    /// receives the range to replace and the replacement string.
    var performEdit: ((NSRange, String) -> Void)?

    /// Applies a replacement either through the host's undo-registering hook or directly.
    private func applyEdit(_ range: NSRange, _ replacement: String) {
        if let performEdit {
            performEdit(range, replacement)
        } else {
            storage?.replaceCharacters(in: range, with: replacement)
        }
    }

    // MARK: Generate

    func beginGenerate(in storage: NSTextStorage, at location: Int) {
        guard mode == .idle else { return }
        self.storage = storage
        mode = .generate
        originalRange = nil
        newRange = NSRange(location: location, length: 0)
    }

    // MARK: Rewrite

    func beginRewrite(in storage: NSTextStorage, selection: NSRange) {
        guard mode == .idle else { return }
        self.storage = storage
        mode = .rewrite
        originalRange = selection
        // New text starts immediately after the original selection.
        newRange = NSRange(location: selection.location + selection.length, length: 0)
    }

    // MARK: Streaming

    /// Appends a streamed text delta at the end of the current `newRange`.
    func appendDelta(_ text: String) {
        guard storage != nil, var nr = newRange, mode != .idle else { return }
        let insertAt = nr.location + nr.length
        applyEdit(NSRange(location: insertAt, length: 0), text)
        nr.length += (text as NSString).length
        newRange = nr
    }

    /// Stops streaming. Generate finishes immediately (nothing to accept);
    /// rewrite remains pending so the user can accept/reject the partial.
    func cancel() {
        if mode == .generate { finishGenerate() }
    }

    // MARK: Resolution

    /// Generate has no diff — once done, there's nothing to accept; just clear state.
    private func finishGenerate() {
        mode = .idle
        originalRange = nil
        newRange = nil
    }

    /// Rewrite accept: delete the original, keep the new text. No-op in any other mode.
    func accept() {
        guard mode == .rewrite else { return }
        guard let orig = originalRange else {
            // Defensive: rewrite mode but no range — clear and bail.
            mode = .idle; originalRange = nil; newRange = nil
            return
        }
        // The new text sits immediately after the original; deleting the original
        // shifts the new text left into the original's place.
        applyEdit(orig, "")
        mode = .idle; originalRange = nil; newRange = nil
    }

    /// Rewrite reject: delete the streamed new text, restore the original. No-op in any other mode.
    func reject() {
        guard mode == .rewrite else { return }
        guard let nr = newRange else {
            mode = .idle; originalRange = nil; newRange = nil
            return
        }
        applyEdit(nr, "")
        mode = .idle; originalRange = nil; newRange = nil
    }

    /// Clears all session state WITHOUT mutating the text storage. Use when the
    /// underlying document is being replaced wholesale (note/tab switch), where
    /// touching the old ranges would corrupt the new document or crash.
    func resetWithoutMutating() {
        mode = .idle
        originalRange = nil
        newRange = nil
    }

    /// Removes the streamed output and returns to idle, leaving the document as it
    /// was *before* this session's generation. In generate mode this deletes the
    /// inserted text; in rewrite mode it deletes the new text and keeps the original
    /// (same end state as `reject()`). Used by Retry so a re-run starts clean instead
    /// of appending onto the previous output.
    func discardOutput() {
        guard mode != .idle else { return }
        if let nr = newRange, nr.length > 0,
           (storage == nil || NSMaxRange(nr) <= storage!.length) {
            applyEdit(nr, "")
        }
        mode = .idle
        originalRange = nil
        newRange = nil
    }
}
