# Reveal Current Block's Raw Markdown — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When hide-markdown-while-typing is on, reveal the raw markdown (dimmed) for the entire parsed block the caret is in, re-hiding when the caret leaves the block.

**Architecture:** A new pure struct `MarkdownPreviewBlockReveal` computes the set of ranges to un-hide for the caret's block — the *inverse of the hide pass*, reusing `MarkdownPreviewSemanticHiding` plus the same bold/italic/code delimiter regexes, intersected with the caret's block range. `LinkAwareTextView` applies dim color + a content-appropriate font over those ranges, gated so it only recomputes when the caret crosses into a different block. It hooks into the instant + debounced selection paths added earlier this session and into `applyPreviewStyling`'s reveal tail.

**Tech Stack:** Swift, AppKit (`NSTextStorage`/`NSTextView`), XCTest. Project uses XcodeGen (`project.yml`, directory-based sources — new files in `SynapseNotes/` and `SynapseNotesTests/` are auto-included on `xcodegen generate`). Test target imports `@testable import Synapse`. Scheme: `Synapse`.

**Repo rule:** Per `.agents/REPO_RULES.md`, after the `.swift` changes the app MUST be rebuilt + relaunched (RELOAD-MAC) before requesting feedback or git operations. No trailing whitespace.

---

## File Structure

- **Create** `macOS/SynapseNotes/MarkdownPreviewBlockReveal.swift` — pure struct: `(source, cursorLocation, isEditable) -> revealedRanges` for the caret's block. Mirrors `MarkdownPreviewCursorReveal` / `MarkdownPreviewSemanticHiding`.
- **Create** `macOS/SynapseTests/MarkdownPreviewBlockRevealTests.swift` — unit tests for the pure struct.
- **Modify** `macOS/SynapseNotes/EditorView.swift` — add `revealCurrentBlockMarkdownAtCursor(document:)` + `lastRevealedBlockRange` to `LinkAwareTextView`; call it from `applyPreviewStyling`'s tail, from `textViewDidChangeSelection` (instant), and reset it in `setPlainText`.

Note: the bold/italic/code delimiter regexes are duplicated between `applyPreviewStyling` (hide) and `MarkdownPreviewBlockReveal` (reveal). Both use the same patterns so they stay in lockstep; the patterns are copied verbatim (DRY is served by them being identical literals derived from the same source of truth — the hide pass — not by premature extraction that would entangle `LinkAwareTextView` internals).

---

## Task 1: Pure block-reveal range computation

**Files:**
- Create: `macOS/SynapseNotes/MarkdownPreviewBlockReveal.swift`
- Test: `macOS/SynapseTests/MarkdownPreviewBlockRevealTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `macOS/SynapseTests/MarkdownPreviewBlockRevealTests.swift`:

```swift
import XCTest
@testable import Synapse

final class MarkdownPreviewBlockRevealTests: XCTestCase {
    func test_make_revealsHeadingPrefixWhenCursorOnHeading() {
        let markdown = "# Title\n\nBody text here"
        let ns = markdown as NSString
        let cursor = ns.range(of: "Title").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "# ")))
    }

    func test_make_revealsBoldDelimitersWithinWrappedParagraph() {
        let markdown = "Some text with **bold phrase** in the middle of a long paragraph."
        let ns = markdown as NSString
        let cursor = ns.range(of: "bold phrase").location + 2

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        // Both ** delimiters revealed.
        XCTAssertEqual(reveal.revealedRanges.filter { ns.substring(with: $0) == "**" }.count, 2)
    }

    func test_make_revealsBothFencesWhenCursorInsideCodeBlock() {
        let markdown = "```swift\nlet value = 1\nlet other = 2\n```"
        let ns = markdown as NSString
        let cursor = ns.range(of: "let value").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "```swift")))
        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "```", options: .backwards)))
    }

    func test_make_revealsNothingWhenCursorOnBlankLineBetweenBlocks() {
        let markdown = "# Title\n\nBody"
        let ns = markdown as NSString
        // The blank line is the \n\n gap; cursor on the empty second line.
        let cursor = ns.range(of: "\n\n").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.isEmpty)
    }

    func test_make_revealsNothingWhenNotEditable() {
        let markdown = "# Title"
        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: 2, isEditable: false)
        XCTAssertTrue(reveal.revealedRanges.isEmpty)
    }

    func test_make_doesNotRevealDelimitersOutsideCaretBlock() {
        let markdown = "**first** bold\n\n**second** bold"
        let ns = markdown as NSString
        let cursor = ns.range(of: "first").location

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        // No revealed range may fall in the second block (after the blank line).
        let secondBlockStart = ns.range(of: "second").location - 2
        XCTAssertFalse(reveal.revealedRanges.contains { $0.location >= secondBlockStart })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd "/Users/dep/Sites/synapse-notes/macOS" && xcodegen generate && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" test -only-testing:SynapseTests/MarkdownPreviewBlockRevealTests 2>&1 | tail -30
```
Expected: FAIL — compile error `Cannot find 'MarkdownPreviewBlockReveal' in scope`.

- [ ] **Step 3: Write the implementation**

Create `macOS/SynapseNotes/MarkdownPreviewBlockReveal.swift`:

```swift
import Foundation

/// Computes the set of previously-hidden markdown syntax ranges to *reveal* for the
/// single parsed block the caret is currently inside, when hide-markdown-while-typing
/// is active. This is the inverse of the hide pass in `applyPreviewStyling`: it reuses
/// `MarkdownPreviewSemanticHiding` for structural/inline tokens and the same
/// bold/italic/inline-code delimiter regexes, then intersects everything with the
/// caret's block range so only the current block reveals.
struct MarkdownPreviewBlockReveal {
    let revealedRanges: [NSRange]
    /// The range of the block the caret is in (nil when the caret is in no block).
    /// Callers use this to skip recomputation while the caret stays in one block.
    let blockRange: NSRange?

    static func make(from source: String, cursorLocation: Int, isEditable: Bool, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownPreviewBlockReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewBlockReveal(revealedRanges: [], blockRange: nil)
        }

        let document = parser.parse(source)
        let ns = source as NSString

        // Find the block containing the caret. A caret exactly at a block's end
        // boundary still counts as inside that block (matches the inline-reveal rule).
        guard let block = document.blocks.first(where: { block in
            cursorLocation >= block.range.location &&
            cursorLocation <= block.range.location + block.range.length
        }) else {
            return MarkdownPreviewBlockReveal(revealedRanges: [], blockRange: nil)
        }

        var ranges: [NSRange] = []

        // 1. Structural + inline-token hidden ranges (headings, blockquote markers,
        //    fence lines, frontmatter fences, link/wikilink/embed/highlight delimiters).
        let hiding = MarkdownPreviewSemanticHiding.make(from: document, isEditable: isEditable)
        for range in hiding.hiddenRanges where NSIntersectionRange(range, block.range).length > 0 {
            ranges.append(range)
        }

        // 2. Bold/italic/inline-code delimiter ranges (NOT part of hiddenRanges; the hide
        //    pass applies these via regex). Same patterns as applyPreviewStyling, scoped
        //    to the block range so we only reveal the caret's block.
        let blockText = ns.substring(with: block.range)
        let base = block.range.location

        func appendGroup(_ pattern: String, group: Int) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let blockNS = blockText as NSString
            regex.enumerateMatches(in: blockText, options: [], range: NSRange(location: 0, length: blockNS.length)) { match, _, _ in
                guard let match, match.numberOfRanges > group else { return }
                let r = match.range(at: group)
                guard r.location != NSNotFound else { return }
                ranges.append(NSRange(location: base + r.location, length: r.length))
            }
        }

        // Bold **text** / __text__
        appendGroup("(\\*\\*)(.+?)(\\*\\*)", group: 1)
        appendGroup("(\\*\\*)(.+?)(\\*\\*)", group: 3)
        appendGroup("(__)(.+?)(__)", group: 1)
        appendGroup("(__)(.+?)(__)", group: 3)
        // Italic *text* (not **)
        appendGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 1)
        appendGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 3)
        // Inline code `code` (skip when the block IS a fenced code block — its content
        // is shown verbatim and the fences are already covered by hiddenRanges above).
        if case .fencedCodeBlock = block.kind {
            // no inline-code delimiters to reveal inside a code block
        } else {
            appendGroup("(`)((?:[^`\\n])+)(`)", group: 1)
            appendGroup("(`)((?:[^`\\n])+)(`)", group: 3)
        }

        return MarkdownPreviewBlockReveal(revealedRanges: dedupe(ranges), blockRange: block.range)
    }

    private static func dedupe(_ ranges: [NSRange]) -> [NSRange] {
        var seen: Set<String> = []
        var result: [NSRange] = []
        for range in ranges where range.location != NSNotFound && range.length > 0 {
            let key = "\(range.location):\(range.length)"
            if seen.insert(key).inserted { result.append(range) }
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd "/Users/dep/Sites/synapse-notes/macOS" && xcodegen generate && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" test -only-testing:SynapseTests/MarkdownPreviewBlockRevealTests 2>&1 | tail -30
```
Expected: PASS — all 6 tests in `MarkdownPreviewBlockRevealTests` succeed (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**

```bash
cd "/Users/dep/Sites/synapse-notes" && git add "macOS/SynapseNotes/MarkdownPreviewBlockReveal.swift" "macOS/SynapseTests/MarkdownPreviewBlockRevealTests.swift" "macOS/Synapse Notes.xcodeproj/project.pbxproj" && git commit -m "$(printf 'feat(macOS): pure block-reveal range computation for hide-markdown\n\nComputes the markdown syntax ranges to un-hide for the parsed block the\ncaret is in (inverse of the applyPreviewStyling hide pass). Pure and\nunit-tested, mirroring MarkdownPreviewCursorReveal.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: Apply the block reveal in the editor with block-change gating

**Files:**
- Modify: `macOS/SynapseNotes/EditorView.swift` — `LinkAwareTextView`: add stored property `lastRevealedBlockRange`, method `revealCurrentBlockMarkdownAtCursor(document:)`; call from `applyPreviewStyling` tail (~line 1616-1619), from `textViewDidChangeSelection` instant path (~line 1071), and reset in `setPlainText` (~line 1480).

There is no unit test for this task — it mutates live `NSTextStorage` attributes on `LinkAwareTextView`, which requires a running text view. The range logic it depends on is fully covered by Task 1's tests. Verification is the build + manual relaunch in Task 3.

- [ ] **Step 1: Add the `lastRevealedBlockRange` stored property**

In `EditorView.swift`, find the `LinkAwareTextView` property declarations near `lastAppliedEditorDisplayMode` / `lastSearchHighlightRanges`. Add:

```swift
    /// The parsed block range whose markdown is currently revealed under the caret.
    /// Used to skip re-revealing while the caret stays within one block.
    private var lastRevealedBlockRange: NSRange?
```

- [ ] **Step 2: Add the `revealCurrentBlockMarkdownAtCursor` method**

In `EditorView.swift`, immediately AFTER the existing `revealSemanticInlineMarkdownAtCursor()` method (which ends around line 1657 with its closing `}`), add:

```swift
    /// Reveals the raw markdown syntax (dimmed) for the entire parsed block the caret
    /// is in, so editing always shows the syntax for the block being edited. Re-hiding
    /// of the block the caret *left* is handled by the next full applyPreviewStyling pass.
    /// No-ops when the caret stays within the same block as the previous call.
    func revealCurrentBlockMarkdownAtCursor(document: MarkdownDocument? = nil) {
        guard isEditable, let storage = textStorage else { return }
        let cursor = selectedRange().location
        // The optional `document` lets callers avoid an extra parse when they already
        // hold one (its `source` is authoritative); otherwise read the live storage.
        let source = document?.source ?? storage.string
        let reveal = MarkdownPreviewBlockReveal.make(from: source, cursorLocation: cursor, isEditable: isEditable)

        // Block-change gating: if the caret is still in the same block we revealed last
        // time, there is nothing new to reveal.
        if let last = lastRevealedBlockRange, let current = reveal.blockRange, NSEqualRanges(last, current) {
            return
        }
        lastRevealedBlockRange = reveal.blockRange

        guard !reveal.revealedRanges.isEmpty else { return }

        // The hidden delimiters were zeroed to systemFont(0.001); restore a visible
        // body-sized font and dim color. Body font reads cleanly for every delimiter
        // kind (**, *, `, [, ]], #, ``` ); surrounding content keeps its own font from
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
```

Note on the font (conscious deviation from the spec): the spec mentioned per-kind fonts (heading/mono/body), but the simplest correct implementation uses a single body-sized dim font for all revealed delimiters. The hidden delimiters were zeroed to `systemFont(0.001)`, so any visible font restores them; body size reads cleanly for `**`, `*`, `` ` ``, `[`, `]]`, `#`, and ``` ``` ```. Surrounding content glyphs keep their own heading/mono font from `applyMarkdownStyling`. This avoids re-deriving a font per range with no visible downside. If later polish wants a heading-sized `#`, the block kind is available on `reveal.blockRange` — out of scope here.

- [ ] **Step 3: Call it from `applyPreviewStyling`'s reveal tail**

In `EditorView.swift`, find the tail of `applyPreviewStyling` (around lines 1615-1619):

```swift
        // After hiding, reveal the wikilink/image embed the cursor is currently inside.
        if isEditable {
            revealSemanticInlineMarkdownAtCursor()
            revealCalloutHeaderAtCursor(document: parsedDocument)
        }
```

Change to:

```swift
        // After hiding, reveal the raw markdown for the block the caret is in (plus the
        // inline-token / callout-header reveals for the cross-block cases they cover).
        if isEditable {
            // A full restyle re-hides everything, so force the block reveal to recompute.
            lastRevealedBlockRange = nil
            revealCurrentBlockMarkdownAtCursor(document: parsedDocument)
            revealSemanticInlineMarkdownAtCursor()
            revealCalloutHeaderAtCursor(document: parsedDocument)
        }
```

- [ ] **Step 4: Call it from the instant selection path**

In `EditorView.swift`, find `textViewDidChangeSelection` in `Coordinator`. The instant reveal currently reads:

```swift
            // Revealing the raw markdown under the caret is the immediate visual
            // feedback the user expects, so it runs synchronously on every move.
            tv.revealSemanticInlineMarkdownAtCursor()
```

Change to:

```swift
            // Revealing the raw markdown under the caret is the immediate visual
            // feedback the user expects, so it runs synchronously on every move.
            // The block reveal no-ops while the caret stays within one block.
            tv.revealCurrentBlockMarkdownAtCursor()
            tv.revealSemanticInlineMarkdownAtCursor()
```

- [ ] **Step 5: Reset the gate on new content in `setPlainText`**

In `EditorView.swift`, in `setPlainText(_ plain:)` (around lines 1474-1481), find:

```swift
        // Stale ranges from a previous file would crash reapplySearchHighlights
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
```

Add immediately after those two lines:

```swift
        // New content invalidates the revealed-block gate so the next caret move
        // re-evaluates against the new document.
        lastRevealedBlockRange = nil
```

- [ ] **Step 6: Build to verify it compiles**

Run:
```bash
cd "/Users/dep/Sites/synapse-notes/macOS" && xcodegen generate && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

- [ ] **Step 7: Commit**

```bash
cd "/Users/dep/Sites/synapse-notes" && git add "macOS/SynapseNotes/EditorView.swift" && git commit -m "$(printf 'feat(macOS): reveal current block raw markdown at cursor\n\nWhen hide-markdown-while-typing is on, the parsed block the caret is in\nshows its raw markdown dimmed, re-hiding when the caret leaves the block.\nGated to recompute only on block change; reuses the selection-styling\ndebounce. Reveal set is the inverse of the applyPreviewStyling hide pass.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: Full test run + mandatory rebuild & relaunch

**Files:** none (verification only).

- [ ] **Step 1: Run the full markdown-preview test suite**

Run:
```bash
cd "/Users/dep/Sites/synapse-notes/macOS" && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" test -only-testing:SynapseTests/MarkdownPreviewBlockRevealTests -only-testing:SynapseTests/MarkdownPreviewSemanticHidingTests -only-testing:SynapseTests/MarkdownPreviewCursorRevealTests -only-testing:SynapseTests/PreviewModeTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` — no regressions in the existing hide/reveal/preview tests.

- [ ] **Step 2: Mandatory rebuild & relaunch (REPO_RULES.md)**

Run:
```bash
cd "/Users/dep/Sites/synapse-notes/macOS" && pkill -9 "Synapse Notes" || true; pkill -9 "Synapse" || true; sleep 1; xcodegen generate && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" && for app in ~/Library/Developer/Xcode/DerivedData/Synapse*-*/Build/Products/Debug/"Synapse Notes.app"; do [ -e "$app" ] && open "$app" && break; done
```
Expected: `** BUILD SUCCEEDED **` and the app launches.

- [ ] **Step 3: Manual verification (hand off to user)**

In the running app, with **hide markdown while typing ON**, open a note containing a heading, a paragraph with `**bold**` that wraps, and a fenced code block. Confirm:
1. Arrowing onto the heading line reveals `# ` dimmed; leaving it re-hides.
2. Caret inside the bold paragraph reveals `**` delimiters dimmed; moving within the same paragraph does not re-flicker.
3. Caret inside the code block reveals both ``` fences; leaving re-hides.
4. Caret on a blank line reveals nothing.
5. Typing speed is unaffected (the block reveal is gated + the re-hide is debounced).

---

## Notes for the executor

- **Do not** introduce trailing whitespace (REPO_RULES.md).
- **Do not** revert unrelated working-tree changes — the three perf fixes (`AppState.swift`, `TabBarView.swift`, parts of `EditorView.swift`) and the regenerated `project.pbxproj` are intentional prior work on this branch; leave them.
- The branch is `feat/reveal-current-block-markdown`.
- `MarkdownTheme.dimColor`, `MarkdownTheme.bodyFont(for:)`, `MarkdownTheme.body` already exist in `EditorView.swift` (lines ~1180, ~1275). `settings` is an optional `SettingsManager?` on `LinkAwareTextView` (the `!`-unwrap pattern matches `applyMarkdownStyling`).
- `xcodegen generate` regenerates `project.pbxproj`; commit it with Task 1 since the new source/test files must be registered in the project.
```
