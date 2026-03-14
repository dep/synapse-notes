# Synapse

A minimal macOS markdown editor with a built-in terminal, wiki links, quick open, and inline image previews.

<img width="1582" height="1035" alt="image" src="https://github.com/user-attachments/assets/f409440d-0d11-49c2-bb38-04ba16ce61d6" />

## Requirements

- macOS 14+
- Xcode 16+
- Homebrew
- `xcodegen`

Install `xcodegen` if needed:

```bash
brew install xcodegen
```

## Build And Run

Preferred: run it entirely from the CLI.

1. Generate the Xcode project:

```bash
xcodegen generate
```

2. Build the app:

```bash
xcodebuild -project "Synapse.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build
```

3. Launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/Synapse-*/Build/Products/Debug/Synapse.app
```

Or do all three steps in one shot:

```bash
xcodegen generate && xcodebuild -project "Synapse.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build && open ~/Library/Developer/Xcode/DerivedData/Synapse-*/Build/Products/Debug/Synapse.app
```

The app is built into Xcode DerivedData under the Debug products folder.

## Run In Xcode

If you prefer Xcode:

```bash
open Synapse.xcodeproj
```

Then select the `Synapse` scheme and press `Cmd-R`.

## Testing

Run tests from the command line:

```bash
xcodebuild test -scheme Synapse -destination 'platform=macOS'
```

Or run tests in Xcode:

1. Open the project: `open Synapse.xcodeproj`
2. Select the `Synapse` scheme
3. Press `Cmd-U` to run all tests

The test suite includes:
- Core `AppState` lifecycle tests
- File and folder CRUD operations
- Navigation history
- Relative path formatting
- Wiki-link and backlink resolution

## Release Build And Notarization

To create a shareable macOS build, use a Release archive signed with `Developer ID Application`, then notarize and staple it.

Prerequisites:

- A valid `Developer ID Application` certificate with private key installed in your login keychain
- A configured notarization profile for `notarytool` (example: `Synapse-notary`)
- `project.yml` must remain the source of truth for release signing settings; do not rely on Xcode-only UI changes because `xcodegen generate` will overwrite them

Create a signed Release archive:

```bash
xcodegen generate && \
xcodebuild archive \
  -project "Synapse.xcodeproj" \
  -scheme "Synapse" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/Synapse.xcarchive"
```

Package the app for notarization:

```bash
ditto -c -k --keepParent \
  "/tmp/Synapse.xcarchive/Products/Applications/Synapse.app" \
  "/tmp/Synapse.zip"
```

Submit, wait, and staple:

```bash
xcrun notarytool submit "/tmp/Synapse.zip" --keychain-profile "Synapse-notary" --wait && \
xcrun stapler staple "/tmp/Synapse.xcarchive/Products/Applications/Synapse.app" && \
spctl --assess --type execute --verbose=4 "/tmp/Synapse.xcarchive/Products/Applications/Synapse.app"
```

Expected successful validation output includes:

- `accepted`
- `source=Notarized Developer ID`

Artifacts:

- notarized app: `/tmp/Synapse.xcarchive/Products/Applications/Synapse.app`
- shareable zip: `/tmp/Synapse.zip`

## Features

### Core Editing
- **Live Markdown Styling** - See bold, italics, links, and code blocks styled as you type
- **Slash Commands** - Type `/time`, `/date`, `/todo`, or `/note` at the start of a line or after a space to insert content inline
- **Wiki Links** - Link to other notes using `[[Note Name]]` syntax with automatic backlink tracking
- **Embeddable Notes** - Include other notes inline using `![[Note Name]]` syntax
- **Inline Image Previews** - View images directly in the editor
- **Hashtag Support** - Tag notes with `#hashtag` syntax for organization
- **Split Panes** - Work with vertical or horizontal editor splits
- **Tab Management** - Multiple tabs with MRU (Most Recently Used) switching

### Navigation & Search
- **Quick Open** - Command palette for fast file access (`⌘P` or `⌘K`)
- **Command Palette** - Quick access to templates and files
- **Find in Note** - Search within current file (`⌘F`)
- **Global Search** - Search across all notes (`⌘⇧F`)
- **History Navigation** - Go back/forward through file history (`⌘[` / `⌘]`)
- **Backlinks** - See which notes link to the current note

### Graph Visualization
- **Local Graph** - 1-hop view of connections from current note
- **Global Graph** - Full vault force-directed graph with zoom and pan
- **Ghost Nodes** - Unresolved wiki links appear as ghost nodes
- **Interactive** - Click nodes to navigate, drag to rearrange

### Terminal Integration
- **Built-in Terminal** - ZSH terminal pane integrated in the sidebar
- **On-boot Command** - Configure commands to run when terminal loads

### Git Sync
- **Auto-commit** - Automatically stage changes
- **Auto-push** - Push to remote on intervals
- **Conflict Detection** - Visual indicators for merge conflicts
- **Sync Status** - Cloud icon shows sync state

### Daily Notes & Templates
- **Daily Notes** - Auto-create dated notes with customizable templates
- **Templates** - Create notes from templates with variables:
  - `{{year}}` - Current year (4 digits)
  - `{{month}}` - Current month (01-12)
  - `{{day}}` - Current day (01-31)
  - `{{hour}}` - Current hour (12-hour format)
  - `{{minute}}` - Current minute (00-59)
  - `{{ampm}}` - AM/PM indicator
  - `{{cursor}}` - Position cursor here after insertion
- **Template Picker** - Choose from available templates when creating notes

### Pinning
- **Pin Notes, Folders, and Tags** - Right-click any file or folder in the file tree, or any tag in the Tags pane, and select **Pin** to add it to the Pinned section
- Pinned items appear above the file tree for instant access
- Click a pinned note to open it; `Cmd+click` to open in a new tab
- Click a pinned folder to expand/scroll to it in the tree
- Click a pinned tag to open a filtered tag view in a new tab
- Pins are vault-specific and persist across restarts; stale pins are cleaned up automatically

### Customizable Sidebar
Drag and drop panes between left and right sidebars:
- **Files** - File tree with folders and markdown files
- **Tags** - Hashtag index with counts
- **Related** - Backlinks and outgoing links
- **Terminal** - Integrated ZSH terminal
- **Graph** - Local graph view

### Publishing
- **Gist Publishing** - Publish notes to GitHub Gists (requires GitHub PAT)

### Vault-Specific Settings
Settings automatically sync with your vault. When you open a vault, Synapse stores its settings in `.noted/settings.yml` at the vault root:
- Settings travel with the vault — perfect for syncing via Git or cloud storage
- Each vault has its own independent settings
- The `.noted` folder is visible in the file tree and can be committed to version control
- Your GitHub Personal Access Token stays local in `~/Library/Application Support/Synapse/settings.yml` (never leaves your machine)

## Keyboard Shortcuts

### File & Note Operations
| Action | Shortcut |
|--------|----------|
| New Note | `⌘N` |
| New Untitled Note | `⌘T` |
| Open Folder / Vault | `⇧⌘O` |
| Close Vault / Exit | `⇧⌘N` |
| Save | `⌘S` |
| Command Palette / Quick Open | `⌘K` or `⌘P` |

### Search
| Action | Shortcut |
|--------|----------|
| Find in Note | `⌘F` |
| Find in All Notes | `⇧⌘F` |
| Find Next | `⌘G` |
| Find Previous | `⇧⌘G` |

## Slash Commands

Type a slash command at the start of a line or after a space — it expands automatically as you finish typing.

| Command | Inserts |
|--------|---------|
| `/time` | Current time like `2:34 pm` |
| `/date` | Current date like `2026-03-14` |
| `/todo` | `- [ ] ` |
| `/note` | `> **Note:** ` |

### Tabs & Navigation
| Action | Shortcut |
|--------|----------|
| Close Tab | `⌘W` |
| Close Other Tabs | `⇧⌘W` |
| Reopen Closed Tab | `⇧⌘T` |
| Switch to Tab 1-8 | `⌘1` - `⌘8` |
| Switch to Last Tab | `⌘9` |
| Go Back (History) | `⌘[` |
| Go Forward (History) | `⌘]` |
| Previous Tab | `⇧⌘[` |
| Next Tab | `⇧⌘]` |
| Cycle MRU Tabs | `⌃Tab` |

### Split Panes
| Action | Shortcut |
|--------|----------|
| Split Vertical | `⌘D` |
| Split Horizontal | `⇧⌘D` |
| Switch Pane (Vertical) | `⌘⌥←` / `⌘⌥→` |
| Switch Pane (Horizontal) | `⌘⌥↑` / `⌘⌥↓` |

### Other Shortcuts
| Action | Shortcut |
|--------|----------|
| Open Global Graph | `⇧⌘G` |
| Open Today's Note | `⌃⌘H` |
| Toggle Sidebar | Click sidebar icons |

## Markdown Guide

Synapse uses standard Markdown with extended features for knowledge management.

### Basic Syntax

```markdown
# Heading 1
## Heading 2
### Heading 3

**Bold text**
*Italic text*
~~Strikethrough~~

- Bullet point
- Another bullet
  - Nested bullet

1. Numbered item
2. Another item

> Blockquote
> Multiple lines

`inline code`

```code block```

[Link text](https://example.com)
![Image alt text](image.png)
```

### Wiki Links

Link to other notes in your vault:

```markdown
[[Note Title]]
[[Note Title|Display Text]]  (with custom display text)
[[Note Title#Section]]       (link to heading)
```

Wiki links are:
- **Case-insensitive** - `[[My Note]]` matches `my note.md`
- **Bidirectional** - See backlinks in the Related pane
- **Clickable** - Click to navigate, Cmd+click to open in new tab

### Embeddable Notes

Include content from another note inline:

```markdown
![[Note Title]]
```

Embeds render the referenced note's content directly in the editor. Nested embeds are automatically converted to wiki links to prevent infinite recursion.

### Hashtags

Tag your notes for organization:

```markdown
#work #project-a #meeting-notes
```

Tags must:
- Start with `#`
- Contain at least one letter
- Can include numbers, hyphens, underscores, and dots
- Are normalized to lowercase

### Templates

Use variables in templates for dynamic content:

```markdown
# {{year}}-{{month}}-{{day}} Daily Note

Time: {{hour}}:{{minute}} {{ampm}}

{{cursor}}
```

### File Structure

Synapse works with regular markdown files on your filesystem:

```
MyVault/
├── notes/
│   ├── idea.md
│   └── project.md
├── daily/
│   └── 2026-03-12.md
├── templates/
│   ├── meeting.md
│   └── daily.md
└── assets/
    └── image.png
```

- No proprietary formats - your data is always accessible
- Git-friendly - version control your entire vault
- Portable - open any folder containing markdown files

## Notes

- The project uses `SwiftTerm` via Swift Package Manager.
- If you add new source files, regenerate the project with `xcodegen generate` before building.
