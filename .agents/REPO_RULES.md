### Important Repo Rules:

1. Always kill, rebuild, and restart the app after making changes to the codebase.

```
xcodegen generate && xcodebuild -project "Noted.xcodeproj" -scheme "Noted" -destination "platform=macOS" build && open ~/Library/Developer/Xcode/DerivedData/Noted-*/Build/Products/Debug/Noted.app
```

2. Release/distribution changes must be reflected in `project.yml`, not only in Xcode UI. This repo uses `xcodegen`, so signing or hardened runtime changes made only in Xcode will be overwritten the next time the project is generated.

3. For a notarized release build, use this flow:

```
xcodegen generate && \
xcodebuild archive \
  -project "Noted.xcodeproj" \
  -scheme "Noted" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/Noted.xcarchive"

ditto -c -k --keepParent \
  "/tmp/Noted.xcarchive/Products/Applications/Noted.app" \
  "/tmp/Noted.zip"

xcrun notarytool submit "/tmp/Noted.zip" --keychain-profile "noted-notary" --wait && \
xcrun stapler staple "/tmp/Noted.xcarchive/Products/Applications/Noted.app" && \
spctl --assess --type execute --verbose=4 "/tmp/Noted.xcarchive/Products/Applications/Noted.app"
```

4. Release prerequisites:

- `Developer ID Application` certificate with private key installed locally
- notarization credentials stored in a `notarytool` keychain profile (currently `noted-notary`)
- Release signing and hardened runtime configured in `project.yml`

---

## Project Overview

**Noted** is a native macOS markdown note-taking app built with SwiftUI. It is Obsidian-inspired: vault-based (user opens a folder), wikilink-aware, with optional git auto-sync.

---

## Architecture

### Core Files

| File | Role |
|------|------|
| `AppState.swift` | Central `ObservableObject`. All file, tab, history, git, and wikilink state lives here. |
| `ContentView.swift` | Root layout: header bar, left sidebar (file tree + connections pane), editor area (tab bar + editor), right sidebar (terminal). Also owns `NSEvent` key monitor for ctrl-tab. |
| `TabBarView.swift` | Tab strip UI. Purely presentational — all logic in `AppState`. |
| `EditorView.swift` | Markdown editor (NSTextView-backed). |
| `FileTreeView.swift` | Left sidebar file browser. |
| `RelatedLinksPaneView.swift` | Shows outbound links, backlinks, and unresolved wikilinks for the selected note. |
| `CommandPaletteView.swift` | CMD-K / CMD-P overlay palette. |
| `SearchView.swift` | In-file search (CMD-F) and all-files search (CMD-Shift-F). |
| `TerminalPaneView.swift` | Embedded terminal pane (right sidebar). |
| `GitService.swift` | Shell-out wrapper around git CLI. |
| `SettingsManager.swift` | JSON-persisted settings (auto-save, auto-push, file extension filter, on-boot command). Config file at `~/Library/Application Support/Noted/settings.json`. |
| `Theme.swift` | All colors, button styles, and shared UI components (`NotedTheme`, `ChromeButtonStyle`, `PrimaryChromeButtonStyle`, `TinyBadge`, `PanelSurface`). |
| `NotedApp.swift` | App entry point. |

### Key Data Flow

- `AppState` is injected as an `@EnvironmentObject` throughout the view hierarchy.
- File content is stored as a single `@Published var fileContent: String` — the active tab's content.
- Auto-save: `fileContent` is debounced 1 second via Combine and written to disk when `isDirty`.
- File watching: `DispatchSourceFileSystemObject` on the parent directory + 0.75s poll timer for disk-change detection.

---

## Tab System

- `tabs: [URL]` — ordered list of open tab URLs.
- `activeTabIndex: Int?` — index into `tabs`.
- `openFile(_:)` — replaces the current tab (default navigation behavior).
- `openFileInNewTab(_:)` — appends a new tab; switches to existing tab if already open.
- `switchTab(to:)` / `closeTab(at:)` — direct index-based tab ops.
- `tabMRU: [URL]` — most-recently-used order, updated on every tab activation.
- **ctrl-tab** cycles tabs in MRU order via `cycleMostRecentTabs()`. The cycle resets if >1 second passes between keypresses. The key monitor lives in `ContentView.installEventMonitor()`.
- `AppState.init(now:)` accepts an injectable clock (`() -> Date`) — used in tests to control time for the MRU cycle timeout.

---

## Wikilink / Graph Data

`AppState` parses `[[wikilink]]` syntax:

- `wikiLinks(in:)` — regex extracts all `[[...]]` references from a string, normalized (lowercased, strips `|alias` and `#heading`).
- `noteIndex()` — maps normalized note title → URL for all files in vault.
- `relationshipsForSelectedFile()` → `NoteLinkRelationships` — outbound resolved links, inbound backlinks, unresolved references for the selected file.

This is the data foundation for any graph view feature.

---

## Git Integration

- `GitService` wraps git CLI calls (clone, pull --rebase, push, stage, commit, branch, ahead-count, conflict detection).
- Auto-push: every 5 minutes if enabled, and on app termination. Pulls first (rebase), then commits staged changes, then pushes.
- Git runs on a private background queue (`com.noted.git`).
- `gitSyncStatus` enum: `.notGitRepo`, `.idle`, `.pulling`, `.pushing`, `.committing`, `.cloning`, `.upToDate`, `.conflict(String)`, `.error(String)`.

---

## Settings

Settings persist to JSON. Key fields:
- `autoSave: Bool` — debounced 1s write to disk.
- `autoPush: Bool` — git commit + push on save and app quit.
- `fileExtensionFilter: String` — comma-separated glob patterns (e.g. `*.md, *.txt`). Filters which files appear in `allFiles` (used in tree and wikilink index). Does not filter `allProjectFiles`.
- `onBootCommand: String` — shell command run in the terminal pane on vault open.

---

## Theming

All colors and styles are in `NotedTheme` (dark-only currently). Key tokens:
- `accent` — blue `#47A8FA`
- `success` — green
- `textPrimary / textSecondary / textMuted` — white at 92% / 68% / 45% opacity
- `panel`, `panelElevated`, `editorShell`, `row`, `rowBorder`, `border`, `divider`

Reusable UI components: `ChromeButtonStyle`, `PrimaryChromeButtonStyle`, `TinyBadge`, `.notedPanel(radius:)` modifier.

---

## Tests

Tests live in `NotedTests/`. `AppStateTabsTests.swift` covers tab management and MRU cycling. `AppState.init(now:)` is the injectable clock seam for time-dependent tests.

---

## Keyboard Shortcuts (defined in ContentView)

| Shortcut | Action |
|----------|--------|
| CMD-K / CMD-P | Command palette |
| CMD-F | In-file search |
| CMD-Shift-F | All-files search |
| CMD-G / CMD-Shift-G | Next/prev search match |
| CMD-W | Close active tab |
| CMD-Shift-W | Close other tabs |
| CMD-T | New untitled note (in new tab) |
| CMD-Shift-T | Reopen last closed tab |
| CMD-1…9 | Switch to tab by position (9 = last) |
| CMD-[ / CMD-] | Go back / forward in history |
| CMD-Shift-[ / CMD-Shift-] | Previous / next tab |
| CMD-S | Save current file |
| CMD-Shift-O | Open folder |
| CMD-Shift-N | Exit vault |
| Ctrl-Tab | Cycle tabs in MRU order |
