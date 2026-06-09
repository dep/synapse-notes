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
        guard let storage, var nr = newRange, mode != .idle else { return }
        let insertAt = nr.location + nr.length
        storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: text)
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
        guard let storage, let orig = originalRange else {
            // Defensive: rewrite mode but no storage/range — clear and bail.
            mode = .idle; originalRange = nil; newRange = nil
            return
        }
        // The new text sits immediately after the original; deleting the original
        // shifts the new text left into the original's place.
        storage.replaceCharacters(in: orig, with: "")
        mode = .idle; originalRange = nil; newRange = nil
    }

    /// Rewrite reject: delete the streamed new text, restore the original. No-op in any other mode.
    func reject() {
        guard mode == .rewrite else { return }
        guard let storage, let nr = newRange else {
            mode = .idle; originalRange = nil; newRange = nil
            return
        }
        storage.replaceCharacters(in: nr, with: "")
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
        if let storage, let nr = newRange, nr.length > 0, NSMaxRange(nr) <= storage.length {
            storage.replaceCharacters(in: nr, with: "")
        }
        mode = .idle
        originalRange = nil
        newRange = nil
    }
}
