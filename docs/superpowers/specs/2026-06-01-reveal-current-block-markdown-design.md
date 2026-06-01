# Reveal the current block's raw markdown — Design

**Date:** 2026-06-01
**Status:** Approved (design); pending spec review
**Area:** macOS editor (`macOS/SynapseNotes/EditorView.swift` and the markdown styling stack)

## Summary

When **hide-markdown-while-typing** (`settings.hideMarkdownWhileEditing`) is on, the editor
hides markdown syntax tokens (delimiters, sigils, fences) so the text reads like rendered
markdown. Today, only the *inline token directly under the caret* (a wikilink, embed, or callout
header) un-hides as you move.

This feature expands that reveal so the **entire parsed block the caret is in** shows its raw
markdown — dimmed — and re-hides when the caret leaves that block. This matches how editors like
Obsidian/Typora behave and makes editing markdown more intuitive: you always see the syntax for
what you're currently editing.

## Behavior

- **Reveal unit = parsed `MarkdownBlock`** (from `MarkdownDocument`), not a visual line. Blocks
  include: paragraph, heading, unordered/ordered/task list item, blockquote, callout, fenced code
  block, table, frontmatter.
  - A paragraph that *wraps* across several visual lines is one block, so visually-wrapped inline
    spans (e.g. `**bold**` that wraps) reveal cleanly with no split-delimiter problem.
  - A block that genuinely spans source lines (fenced code block, multi-line blockquote) reveals
    as a unit.
- **Fenced code blocks:** when the caret is anywhere inside, **both** the opening and closing
  ` ``` ` fence lines reveal together (and their collapsed line-height is restored).
- **Reveal style:** each previously-hidden delimiter un-hides at the **font of the content it
  decorates**, recolored to `MarkdownTheme.dimColor`. Headings stay heading-sized; inline code
  stays monospace; the small sigils (`#`, `**`, `` ` ``, `[[`, `]]`, `![`, …) appear dim. This is
  consistent with the existing `revealSemanticInlineMarkdownAtCursor` / `revealCalloutHeaderAtCursor`
  behavior (both set `.foregroundColor: MarkdownTheme.dimColor`).
- **Trigger granularity = block change only.** The reveal recomputes only when the caret crosses
  into a *different* parsed block. Moving the caret within the same block is a no-op (no
  re-flicker / no redraw).

## Architecture

This extends the existing hide/reveal mechanism rather than introducing a new one. Three pieces
exist today in `EditorView.swift` (on `LinkAwareTextView`):

1. `applyPreviewStyling(...)` — hides every syntax token by applying
   `hiddenAttrs = [.font: systemFont(0.001), .foregroundColor: .clear]` to the ranges produced by
   `MarkdownPreviewSemanticHiding.make(from:isEditable:)` (plus a few inline regexes for
   bold/italic/code delimiters). At its tail (when `isEditable`) it calls the two reveal helpers
   below.
2. `revealSemanticInlineMarkdownAtCursor()` — un-hides the inline token under the caret via
   `MarkdownPreviewCursorReveal`.
3. `revealCalloutHeaderAtCursor(document:)` — un-hides a callout header under the caret.

### New unit: `revealCurrentBlockMarkdownAtCursor(document:)`

A new method on `LinkAwareTextView`, parallel to the two existing reveal helpers.

**Inputs:** the already-parsed `MarkdownDocument` (passed in; falls back to parsing
`storage.string` if nil, like the existing helpers) and the current caret location
(`selectedRange().location`).

**What it does:**
1. Find the block containing the caret: `document.blocks.first { NSLocationInRange(cursor, $0.range) }`.
   If none (caret on a blank line / between blocks), do nothing.
2. Compute the ranges to reveal as exactly the set that `applyPreviewStyling` hid, intersected
   with the block's `range`. The reveal set is derived from the **same** source as the hide set so
   the two can never drift:
   - `MarkdownPreviewSemanticHiding.make(from: document, isEditable: isEditable).hiddenRanges`
     intersected with the block range (covers heading prefixes, blockquote `>` markers, fence
     lines, frontmatter fences, wikilink/embed/markdownLink/highlight delimiters).
   - The bold/italic/inline-code delimiter ranges that `applyPreviewStyling` hides via regex are
     **not** in `hiddenRanges`; for the current block we reveal them by re-running those same
     (now cached) regexes scoped to the block range and recoloring the delimiter sub-ranges to
     dim. To avoid duplicating the regex list, factor the delimiter-range computation in
     `applyPreviewStyling` into a small shared helper that returns the delimiter ranges for a given
     search range; both hide and reveal call it. (See "Refactor" below.)
3. For each range to reveal, set `.foregroundColor = MarkdownTheme.dimColor` and restore a visible
   font. Note the hidden ranges currently carry the `hiddenAttrs` font (`systemFont(0.001)`), so we
   must **not** read the existing font back at those ranges — it would be the ~0 size. Instead the
   reveal applies an explicit content font chosen by the containing block's kind: the matching
   heading font (`h1Font`…`h4Font` via the same `MarkdownTheme.*(for: settings)` accessors
   `applyMarkdownStyling` uses) for headings, `monoFont` for fenced-code fences and inline-code
   backticks, and `bodyFont` otherwise. Color is always `MarkdownTheme.dimColor`. This mirrors the
   existing reveal helpers, which set an explicit `.font` + dim color rather than reading the
   hidden font back.
4. For fenced code blocks: also restore the opening/closing fence lines' paragraph style
   (`applyPreviewStyling` collapses them to `minimumLineHeight/maximumLineHeight/lineSpacing = 0`)
   back to the normal line metrics so the fences become visible lines again.

The method wraps its mutations in `storage.beginEditing()/endEditing()` like the existing helpers.

### Refactor (in service of this feature, minimal)

`applyPreviewStyling` currently inlines the bold/italic/strikethrough/inline-code delimiter-hiding
regexes. Extract a `markdownDelimiterRanges(in text: NSString, searchRange: NSRange,
fencedCodeBlockRanges: [NSRange]) -> [NSRange]` helper (pure, returns the delimiter ranges).
`applyPreviewStyling` uses it to hide; `revealCurrentBlockMarkdownAtCursor` uses it (scoped to the
block) to know which delimiters to reveal. This keeps hide and reveal in lockstep and is the only
structural change.

### Call sites & block-change gating

- `LinkAwareTextView` gains `private var lastRevealedBlockRange: NSRange?`.
- In `textViewDidChangeSelection` (the **instant** path added earlier this session): call
  `revealCurrentBlockMarkdownAtCursor()`. Internally it computes the caret's block range; if it
  equals `lastRevealedBlockRange`, return immediately (block unchanged → no work). Otherwise update
  `lastRevealedBlockRange` and reveal.
- The **debounced** path (`selectionStylingWorkItem`, also added earlier this session) continues to
  run the full `applyMarkdownStyling` + `applyPreviewStyling` re-hide sweep. That sweep
  re-collapses the block the caret *left* and then (via `applyPreviewStyling`'s tail) re-reveals
  the current block. So:
  - **Instant:** reveal current block (skipped if same block as last).
  - **Debounced:** re-hide everything, then reveal current block.
- `applyPreviewStyling`'s tail (currently calls the two reveal helpers when `isEditable`) also
  calls `revealCurrentBlockMarkdownAtCursor(document: parsedDocument)`, so a full restyle keeps the
  current block revealed.
- `lastRevealedBlockRange` is reset to `nil` in `setPlainText` (new file/tab) and whenever a full
  restyle runs, so the next caret move always re-evaluates.

### Relationship to existing inline/callout reveals

The block reveal is a **superset** of the inline-token and callout-header reveals for the block the
caret is in. The existing two helpers stay (they're cheap and cover the same block harmlessly), so
no behavior regresses; the block reveal simply reveals more of the same block.

## Edge cases

- Caret on a blank line or between blocks → no containing block → nothing revealed.
- `hideMarkdownWhileEditing` off, or read-only mode → feature inert (guarded exactly like the
  existing reveal path: `guard isEditable`, and the selection handler already guards on
  `hideMarkdownWhileEditing` + `.preview` display mode).
- Table / thematic-break blocks → revealing their (few) hidden ranges is harmless; tables have no
  hidden delimiters in `hiddenRanges`, so effectively a no-op.
- Selection (non-empty range) → use the selection's `location` (the caret/anchor) to pick the
  block, same as the existing helpers use `selectedRange().location`.

## Testing

The reveal-range computation is pure and unit-testable, mirroring the existing
`MarkdownPreviewCursorReveal` / `MarkdownPreviewSemanticHiding` tests. Add a test type (or extend
an existing one) that, given a `MarkdownDocument` + cursor location, returns the set of ranges the
block reveal would un-hide, and assert on:

1. **Heading** — caret in `# Title` reveals the `# ` prefix range.
2. **Bold within a wrapped paragraph** — caret in a long paragraph containing `**bold**` reveals
   the `**` delimiter ranges (and nothing outside the block).
3. **Multi-line fenced code block** — caret inside reveals both the opening and closing fence line
   ranges.
4. **Caret outside any block** (blank line) — reveals nothing.
5. **Block-change gating** — same-block caret move yields the same block range (so the call is a
   no-op); cross-block move yields a different range.

Per repo rules (`.agents/REPO_RULES.md`), after the `.swift` changes the app MUST be rebuilt and
relaunched (RELOAD-MAC) before requesting feedback or doing git operations. Manual verification:
turn on hide-markdown, arrow through a note with a heading, a wrapped bold paragraph, and a code
block, and confirm the current block's syntax reveals dim and re-hides on leaving.

## Out of scope (YAGNI)

- No new setting/toggle — the feature is part of hide-markdown-while-typing.
- No per-token reveal animation/fade.
- No change to read/preview (non-editable) rendering.
- No reveal of blocks the caret is not in.
