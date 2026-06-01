# WikiLink Click Respects Markdown Exposure

**Date:** 2026-06-01
**Status:** Approved
**Scope:** macOS app — `EditorView.swift`

## Problem

When a WikiLink's `[[...]]` markdown is *exposed* (visible) in the editor, the link
still looks underlined/clickable, and clicking it navigates to the linked note.
This is confusing: the exposed markdown signals "you are editing this," yet the
click behaves as navigation. A click on exposed markdown should place the caret
for editing instead.

## Rule

A WikiLink click navigates **only when its `[[...]]` markdown is currently hidden.**
The markdown is hidden only when **both**:

1. `hideMarkdownWhileEditing` is ON. (In always-on markdown mode the syntax is
   visible in every block, so no WikiLink click ever navigates.)
2. The clicked character index is **outside** the caret's current block. The caret's
   block has its markdown revealed (active/exposed); every other block is collapsed.

When the markdown is exposed (markdown mode, or a click inside the active block under
hide-while-typing), the click falls through to `NSTextView`'s default handling, which
places the caret where the user clicked.

### Behavior matrix

| Mode | Click location | Result |
|------|----------------|--------|
| Markdown always visible (`hideMarkdownWhileEditing` OFF) | any WikiLink | place caret (never navigates) |
| Hide-while-typing ON | WikiLink in the active (caret) block | place caret |
| Hide-while-typing ON | WikiLink in a collapsed block | navigate (open file / new tab on Cmd) |
| Read-only / unfocused pane (no caret block) | any WikiLink | navigate |

## Implementation

In `EditorView.swift`, the `mouseDown(with:)` override (~line 2466) currently runs the
WikiLink navigation branch unconditionally:

```swift
if let target = wikilinkTarget(at: point) {
    let openInNewTab = event.modifierFlags.contains(.command)
    _ = handleLinkClick(target, openInNewTab: openInNewTab)
    return
}
```

Gate it on a new predicate:

```swift
if let target = wikilinkTarget(at: point) {
    if wikilinkMarkdownIsHidden(at: point) {
        let openInNewTab = event.modifierFlags.contains(.command)
        _ = handleLinkClick(target, openInNewTab: openInNewTab)
        return
    }
    // markdown exposed → fall through so the click places the caret for editing
}
```

New helper `wikilinkMarkdownIsHidden(at:) -> Bool`:

- Returns `false` immediately when `hideMarkdownWhileEditing` is OFF (markdown always
  visible ⇒ never hidden ⇒ never navigates).
- Otherwise computes the clicked character index using the same coordinate math
  `wikilinkTarget(at:)` already uses (`layoutManager.characterIndex(for:in:...)`).
- Computes the caret's current block range via
  `MarkdownPreviewBlockReveal.make(from:cursorLocation:isEditable:).blockRange`,
  using the current selection's location as `cursorLocation`.
- Returns `true` when `blockRange` is nil (no active block — read-only/unfocused) OR
  the clicked index is outside `blockRange`. Returns `false` when the clicked index is
  inside `blockRange` (active block, markdown revealed).

The predicate intentionally reuses the existing block-reveal computation so the
"which block is exposed" answer stays consistent with what `applyPreviewStyling` /
`revealCurrentBlockMarkdownAtCursor` actually render.

## Trade-off (accepted)

Clicking a WikiLink in a collapsed block navigates **instead of** moving the caret into
that block. Collapsed = navigation-only. To edit such a link, the user clicks elsewhere
in the block first (revealing the markdown), then clicks the now-exposed link to place
the caret.

## Out of scope

- Tag clicks, image-embed clicks, task-checkbox clicks — unchanged.
- External-URL link clicks — unchanged (handled inside `handleLinkClick`).
- Hover/cursor (pointing-hand) affordance — not adjusted in this change.

## Verification

Build + RELOAD, then exercise live:

1. Markdown mode (hide OFF): click a WikiLink → caret is placed, no navigation.
2. Hide-while-typing: click a WikiLink in the block the caret is in → caret moves, no
   navigation.
3. Hide-while-typing: click a WikiLink in a different (collapsed) block → navigates;
   Cmd-click opens in a new tab.
