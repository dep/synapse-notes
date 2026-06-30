# Inline AI Editing — Design Spec

**Date:** 2026-06-09
**Status:** Approved design, pending implementation plan
**Scope:** macOS app (`macOS/SynapseNotes`)

## Summary

Add the ability to edit the current note using AI, directly inside the editor:

- A clickable ✨ icon at the end of the active line opens an inline prompt bar; the AI generates text streaming in at the cursor.
- Selecting text shows a ✨ near the selection; clicking it opens the bar in "rewrite" mode, presenting the AI's rewrite as an inline diff (original struck-through, new text green) with Accept / Reject / Retry.
- The user adds an Anthropic API key in Settings (stored in the macOS Keychain) and picks a default model.
- A per-request model picker in the bar toggles between Haiku 4.5, Sonnet 5, and Opus 4.8.
- `@<filename>` / `@<directory>` autocomplete in the prompt field pulls vault notes in as context.
- Generated text streams into the editor live; a Stop button (and Esc) cancels, keeping whatever streamed.

## Goals / Non-Goals

**Goals:** in-flow generation and rewriting, safe (non-destructive) rewrites, streaming UX, secure key storage, vault-note context injection, per-request model choice.

**Non-Goals (YAGNI):** multi-turn chat history, image inputs, tool use, a prompt template library, per-vault key overrides, non-Anthropic providers, recursive `@directory` walking. The model set is exactly Haiku 4.5 / Sonnet 5 / Opus 4.8.

## Architecture

Six cooperating units, each independently testable. New files live in `macOS/SynapseNotes/`.

| Unit | Responsibility | File |
|---|---|---|
| `KeychainStore` | `SecItem` wrapper: get/set/delete the Anthropic API key under one service+account. | `KeychainStore.swift` |
| `AnthropicClient` | Stateless transport. Builds the `/v1/messages` request, streams SSE via `URLSession.bytes(for:)`, emits an `AsyncThrowingStream<String, Error>` of text deltas. Knows model IDs, headers, cancellation. No UI. | `AnthropicClient.swift` |
| `AIRequestBuilder` | Pure function: assembles system + user message from (prompt, current note, selection, resolved `@`-context, mode). All prompt-engineering lives here. | `AIRequestBuilder.swift` |
| `AIContextResolver` | Resolves `@name` tokens → note contents from `appState.allFiles`, applies the ~100K-char cap, returns resolved blocks + a truncation flag. Pure. | `AIContextResolver.swift` |
| `InlineAIController` | Orchestrator. `ObservableObject` owned per-editor. Holds session state (mode, streaming buffer, accepted/pending ranges), drives `AnthropicClient`, applies streamed deltas to the text storage, owns Accept/Reject/Cancel. Bridges AppKit ↔ request/transport units. | `InlineAIController.swift` |
| `InlineAIBarView` + `AISparkleButton` | SwiftUI inline bar (prompt field, model picker, `@`-autocomplete popover, Stop, diff Accept/Reject) hosted via `NSHostingView`; plus the ✨ overlay control mirroring `CollapsibleToggleButton`. | `InlineAIView.swift` |

**Settings:** one new `Section` in `SettingsView.swift` (API key `SecureField` backed by `KeychainStore`, plus a default-model `Picker`), and `SettingsManager` gains a persisted `aiDefaultModel` stored in the machine-local `GlobalConfig` (alongside the GitHub PAT, since model choice is a machine preference, not vault content). The API key is **not** stored in any YAML — only in Keychain.

**Wiring:** `InlineAIController` is created alongside the editor lifecycle (like `EditorState`), handed a reference to the `LinkAwareTextView` and `appState`. The ✨ overlays hook into the existing `LinkAwareTextView` lifecycle: selection/caret changes via `textViewDidChangeSelection` (`EditorView.swift:1061`) and overlay positioning via the same layout-manager pattern as `refreshCollapsibleToggles` (`EditorView.swift:2181`).

## Data Flow & Interaction

### A. The ✨ affordances

Both reuse the proven overlay pattern from `refreshCollapsibleToggles` (`EditorView.swift:2181-2243`): compute a glyph rect with `layoutManager.boundingRect(forGlyphRange:in:)`, offset by `textContainerOrigin`, and position an `NSControl` subview added via `addSubview`. Target/action drives the click.

1. **Active-line ✨** — A new `refreshAISparkle()`, called from the same post-layout point as `refreshCollapsibleToggles` and on selection change (debounced like the existing styling pass — see [[typing-perf-hotpath]] for the un-debounced-caret-move trap; this must not add synchronous work to every caret move), positions a single reused `AISparkleButton` at the end-of-line glyph rect for the caret's line. One button, repositioned — not one-per-line.
2. **Selection ✨** — When `selectedRange().length > 0`, position the same button just past the selection's end rect. Clicking either opens the bar in the matching mode (`.generate` at caret / `.rewrite` over selection).

### B. Generate-at-cursor flow

1. ✨ click → `InlineAIController.begin(.generate, at: caretLocation)`.
2. `InlineAIBarView` (`NSHostingView`) is inserted below the active line; prompt field focused.
3. User types prompt (+ optional `@`-refs) → ⏎.
4. `AIContextResolver(prompt, allFiles)` → resolved context (capped at ~100K chars; truncation flagged).
5. `AIRequestBuilder(.generate, note, caret, context)` → `messages` payload.
6. `AnthropicClient.stream(messages, model)` → `AsyncThrowingStream<String>`.
7. Each delta: `replaceCharacters(in:with:)` at a tracked growing insertion range; cursor follows; existing `didChangeText()` path re-applies markdown styling automatically (no manual refresh).
8. Stop button / Esc cancels the URLSession task (keeps partial). On finish, the generated range is plain text — nothing to accept, just normal undoable text.

### C. Rewrite-selection flow (the inline diff)

1. ✨ on selection → `begin(.rewrite, over: selRange)`.
2. Snapshot original text + range. **Original is never deleted until Accept** — satisfies "never lose your words."
3. Stream NEW text into an insertion point immediately after the selection.
4. Render: original styled struck-through / red, new text streams in green. Diff coloring uses **transient text attributes applied through the existing styling pass** (so it survives re-layout) and is **not persisted to disk** until Accept.
5. **Accept (⏎):** delete the original range, strip diff attributes from the new text → plain text.
6. **Reject (⎋):** delete the streamed new text, restore the original's normal attributes.
7. **Retry (↻):** reject + re-run with the same (or edited) prompt.

> Implementation note on the diff attributes: `applyPreviewStyling()` is a pure hide pass (see [[preview-styling-is-pure-hide]]). The diff strike-through/coloring is a *transient overlay* applied after styling for the duration of the rewrite session and cleared on Accept/Reject — it must not be confused with or baked into the persistent styling passes.

### D. `@`-autocomplete inside the prompt field

The prompt field is a small `NSTextView`/`NSTextField` **in the bar**, not part of the editor's text storage — so it runs its **own** backward-search-for-`@` detection, mirroring the `[[` logic at `EditorView.swift:3256` (search back ≤ N chars for the token start, extract query, gate on length / no closing delimiter). It shows a completion popover anchored to the field, scored with `commandPaletteScoreByFilename()` reused from `CommandPaletteView.swift:15`. Selecting inserts `@name` into the prompt string. Directories are offered too (from the folder set) and suffixed to disambiguate. Resolution of `@name` → note contents happens later, in `AIContextResolver`, not at insertion time.

### E. Implicit context

Every request includes the **full text of the current note** (so "continue this thought" / "summarize above" work) plus any `@`-referenced notes. The rewrite flow additionally includes the selected text as the explicit target. This is assembled in `AIRequestBuilder`.

### F. Cancellation & errors (all surfaced inline in the bar)

- **No API key** → "Add your Anthropic API key in Settings →" with a button that opens Settings; prompt field disabled.
- **401 / invalid key** → "Invalid API key — check Settings."
- **Network failure / non-2xx** → inline message + Retry; any partial stream is kept.
- **`@`-ref to a missing note** → silently skipped, with a small "1 reference not found" note in the bar.
- **Context over cap** → streams anyway with a "Context truncated to fit" warning.
- **Cancel (Stop/Esc)** → URLSession task cancelled, partial text retained, bar moves to the accept/reject state (rewrite) or simply ends (generate).

## Transport details (Anthropic API)

Direct `URLSession` SSE — no SDK dependency (the app has no first-party Swift SDK target; this matches the existing `GistPublisher` URLSession approach at `GistPublisher.swift:1`).

- **Endpoint:** `POST https://api.anthropic.com/v1/messages`
- **Headers:** `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- **Body:** `{ "model": <id>, "max_tokens": 4096, "stream": true, "system": <system>, "messages": [...] }`. No `thinking` block — inline edits want low latency, and omitting thinking is valid for all three models. `max_tokens` 4096 is ample for inline edits and keeps streaming responsive.
- **Model IDs (exact, no date suffixes):** `claude-haiku-4-5`, `claude-sonnet-5`, `claude-opus-4-8`.
- **Streaming:** consume `urlSession.bytes(for: request)` (the `URLSession` is injectable, defaulting to `.shared`, mirroring `GistPublisher` so tests can supply a mocked `URLProtocol`), split on lines, parse `data:` JSON, and for each `{"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}` emit `delta.text`. Stop on `message_stop`. A non-2xx HTTP status maps to a typed error (401 → invalid key, ≥500 → server error).
- **Cancellation:** hold the `Task` running the stream; `cancel()` on Stop/Esc.

## Settings & persistence

- `SettingsView.swift`: add an **"AI"** `Section` after the GitHub Gist section, containing a `SecureField` for the API key (reads/writes `KeychainStore`) and a `Picker` bound to `settings.aiDefaultModel`.
- `SettingsManager.swift`: add `@Published var aiDefaultModel: String` with the existing `didSet { save() }` pattern, persisted in `GlobalConfig` (machine-local). The API key never touches YAML — `KeychainStore` is the single source of truth, read on demand.
- The bar's per-request model picker defaults to `aiDefaultModel`; changing it in the bar updates `aiDefaultModel` so "last used" persists. Default value: `claude-sonnet-5` (speed/quality balance).

## Error Handling

All AI errors surface **inline in the bar**, never as a crash or modal alert. See §F for the specific cases. A missing/invalid key disables the prompt field and points the user to Settings. Network/API errors keep any partial stream and offer Retry.

## Testing

Mirrors the existing `CommandPaletteWikiLinkTests` / `GistPublisher` test style — `URLSession` injected for the client.

- `AIContextResolverTests` — `@name` resolution, case-insensitivity, the cap/truncation, missing refs, directory expansion. Pure, no network.
- `AIRequestBuilderTests` — correct system/user assembly for `.generate` vs `.rewrite`, selection inclusion, context-block formatting. Pure.
- `AnthropicClientTests` — SSE parsing via a mocked `URLProtocol` feeding canned `content_block_delta` bytes: assert the emitted delta stream; assert cancellation halts emission; assert error mapping (401, non-2xx).
- `KeychainStoreTests` — round-trip set/get/delete against a test service name.
- `InlineAIControllerTests` — Accept applies the new text and removes the original; Reject restores the original; Cancel keeps the partial. Driven by a stub client emitting a scripted stream (no real network).

AppKit overlay positioning (the ✨ placement) is verified manually via the mandatory build-and-relaunch, consistent with how the editor's other overlays are validated.

## Key source references (verified)

- Overlay positioning pattern: `EditorView.swift:2181-2243` (`refreshCollapsibleToggles`)
- Selection/caret change hook: `EditorView.swift:1061` (`textViewDidChangeSelection`)
- `[[`-typing detection to mirror for `@`: `EditorView.swift:3256`
- Filename scoring to reuse: `CommandPaletteView.swift:15` (`commandPaletteScoreByFilename`)
- Text mutation API: `replaceCharacters(in:with:)` + `didChangeText()` (used throughout `EditorView.swift`)
- Vault note source: `appState.allFiles` (`AppState.swift:177`)
- Settings UI + persistence pattern: `SettingsView.swift`, `SettingsManager.swift` (GitHub PAT in `GlobalConfig` as the precedent)
- Networking precedent: `GistPublisher.swift:1` (URLSession)
