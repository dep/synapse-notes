---
layout: doc
title: Markdown Guide
---

# Markdown Guide

Synapse supports standard Markdown syntax along with powerful extensions for knowledge management, including wiki links, embeds, and hashtags.

## Basic Syntax

### Headings

Use `#` symbols to create headings:

```markdown
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

### Text Formatting

```markdown
**Bold text**
*Italic text*
***Bold and italic***
~~Strikethrough~~
`Inline code`
```

### Lists

Unordered lists:

```markdown
- Item one
- Item two
- Item three
  - Nested item
  - Another nested item
```

Ordered lists:

```markdown
1. First item
2. Second item
3. Third item
   1. Nested ordered item
   2. Another nested item
```

### Links

Standard Markdown links:

```markdown
[Link text](https://example.com)
[Link with title](https://example.com "Hover text")
[Relative link](./other-note.md)
```

### Images

```markdown
![Alt text](image.png)
![Alt text with title](image.png "Hover description")
```

Images are rendered inline in the editor.

### Blockquotes

```markdown
> This is a blockquote
> It can span multiple lines
>
> > And can be nested
```

### Code Blocks

Inline code with backticks:

```markdown
Use `function()` to call the method
```

Fenced code blocks:

````markdown
```javascript
function greet(name) {
  return `Hello, ${name}!`;
}
```

```python
def greet(name):
    return f"Hello, {name}!"
```
````

### Horizontal Rules

```markdown
---

***

___
```

### Tables

```markdown
| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
```

### Task Lists

```markdown
- [x] Completed task
- [ ] Incomplete task
- [ ] Another task
```

## Synapse Extensions

### Slash Commands

Type a slash command at the start of a line or after a space — it expands automatically as you finish typing, no confirmation needed.

| Command | Inserts |
| --- | --- |
| `/time` | Current time like `2:34 pm` |
| `/date` | Current date like `2026-03-14` |
| `/todo` | `- [ ] ` |
| `/note` | `> **Note:** ` |

### Wiki Links

Wiki links are the foundation of connected notes in Synapse. They create bidirectional links between notes.

**Basic syntax:**

```markdown
[[Note Title]]
```

**With custom display text:**

```markdown
[[Note Title|Click here to read more]]
```

**Link to a specific section:**

```markdown
[[Note Title#Section Heading]]
```

**How wiki links work:**
- **Case-insensitive:** `[[My Note]]` matches `my note.md`, `MY NOTE.md`, etc.
- **Automatic backlinks:** Synapse tracks which notes link to the current note
- **Click to navigate:** Click a wiki link to open that note
- **Link selected text quickly:** Highlight text and press `CMD + K`, then pick a note to insert `[[Note Title|highlighted text]]`
- **Cmd+click:** Open in a new tab
- **Unresolved links:** Links to non-existent notes appear as "ghost" links and are tracked

**Finding backlinks:**
Open the **Related** pane in the sidebar to see:
- Outbound links (notes you link to from the current note)
- Inbound links (notes that link to the current note)
- Unresolved links (links to notes that don't exist yet)

### Embeddable Notes

Embed the content of one note directly into another:

```markdown
![[Note Title]]
```

Embeds are rendered inline in the editor, showing the full content of the referenced note.

**Use cases:**
- Include a common header/footer across multiple notes
- Embed reference material without duplicating content
- Create composite documents from reusable components

**Important notes:**
- Embeds are **not recursive** - nested embeds are automatically converted to regular wiki links
- The embedded content is rendered as read-only text
- Changes to the embedded note automatically update in all notes that embed it

### Hashtags

Tag your notes for organization and filtering:

```markdown
#work #project-a #meeting-notes #todo
```

**Tag rules:**
- Must start with `#`
- Must contain at least one letter (not just numbers)
- Can include letters, numbers, hyphens (`-`), underscores (`_`), and dots (`.`)
- Are normalized to lowercase (`#Work` becomes `work`)

**Viewing and using tags:**
- **Inline:** Tags appear colorized in the editor and are clickable — click any inline tag to open a filtered view of that tag
- **Tags Pane:** Open the **Tags** pane in the sidebar to see all tags used across your vault, with count of notes per tag
- **Click a tag** in the Tags pane to see all notes with that tag

**Examples:**

```markdown
# Valid tags:
#work
#project-2024
#meeting_notes
#v2.1
#00feature

# Invalid (treated as plain text):
#123          (numbers only)
#             (just the symbol)
```

**Tags in URLs are ignored:**

Synapse automatically ignores hashtags that appear inside URLs:

```markdown
This link https://example.com/page#section contains a URL fragment, not a tag.
But this #is-a-real-tag.
```

## Templates

Templates allow you to create notes with dynamic content using variables.

### Template Variables

Use these variables in your templates:

| Variable | Output | Example |
|----------|--------|---------|
| <code v-pre>{{year}}</code> | 4-digit year | 2026 |
| <code v-pre>{{month}}</code> | 2-digit month | 03 |
| <code v-pre>{{day}}</code> | 2-digit day | 12 |
| <code v-pre>{{hour}}</code> | 12-hour format hour | 09 |
| <code v-pre>{{minute}}</code> | 2-digit minute | 45 |
| <code v-pre>{{ampm}}</code> | AM or PM | AM |
| <code v-pre>{{cursor}}</code> | Cursor position | (removed after placement) |

### Example Templates

**Daily Note Template:**

```markdown v-pre
# {{year}}-{{month}}-{{day}} Daily Note

## Morning
{{cursor}}

## Afternoon

## Evening

## Notes
```

**Meeting Template:**

```markdown v-pre
# Meeting: {{year}}-{{month}}-{{day}}

**Time:** {{hour}}:{{minute}} {{ampm}}

**Attendees:** 

**Agenda:**
- 

**Notes:**
{{cursor}}

**Action Items:**
- [ ] 
```

**Project Template:**

```markdown v-pre
# {{year}}-{{month}}-{{day}} - New Project

## Overview
{{cursor}}

## Goals

## Tasks
- [ ] Setup
- [ ] Research
- [ ] Implementation

## Resources
```

### Using Templates

1. Place template files in your configured templates folder (default: `templates/`)
2. Create a new note with `⌘N` or `⌘T`
3. If templates exist, the Command Palette will show available templates
4. Select a template to create a new note with the template content

### Daily Notes

Enable Daily Notes in Settings to automatically create a dated note each day:

1. Go to **Settings > Workflows > Daily Notes**
2. Enable "Daily Notes"
3. Set the folder (default: `daily/`)
4. Choose a template (optional)

When you open your vault, today's note is automatically created if it doesn't exist.

## Best Practices

### File Organization

Organize your vault in a way that makes sense to you:

```
Vault/
├── 00-Inbox/              # Capture new notes here
├── 01-Projects/           # Active projects
├── 02-Areas/              # Ongoing responsibilities
├── 03-Resources/          # Reference material
├── 04-Archive/            # Completed/obsolete notes
├── daily/                 # Daily notes (auto-created)
├── templates/             # Note templates
└── assets/                # Images and attachments
```

### Linking Strategy

1. **Use descriptive titles** - Notes are identified by their filenames
2. **Link liberally** - Connect related concepts with wiki links
3. **Create stub notes** - Link to notes that don't exist yet, then fill them in
4. **Use the graph view** - Visualize connections to find orphaned notes

### Tagging Strategy

1. **Use broad categories** - #work, #personal, #learning
2. **Add specific tags** - #project-name, #meeting, #book-notes
3. **Status tags** - #todo, #in-progress, #done
4. **Don't over-tag** - 2-4 tags per note is usually sufficient

### Writing Tips

1. **Atomic notes** - One concept per note makes linking more powerful
2. **Note titles as sentences** - "How to configure Git sync" vs "Git Config"
3. **Start with context** - Briefly explain what the note is about
4. **Use headers** - Structure long notes with clear headings

## Tips & Tricks

### Keyboard Shortcuts for Editing

While editing:
- **⌘S** - Save current note
- **⌘F** - Find in note
- **⌘G** - Find next
- **⇧⌘G** - Find previous
- **/command** - Slash commands expand inline at line start or after a space

### Navigation Tips

- Use **⌘P** or **⌘K** for Quick Open to jump to any note
- **⌘[** and **⌘]** navigate back/forward through your history
- **⌃Tab** cycles through MRU (most recently used) tabs
- Click any wiki link to navigate, Cmd+click to open in new tab

### Graph View Tips

- **Global Graph** (`⇧⌘G`) shows your entire vault
- **Local Graph** (sidebar pane) shows 1-hop connections
- Drag nodes to rearrange
- Zoom with buttons or trackpad
- Click a node to open that note
- Ghost nodes (dashed) are unresolved wiki links

### Terminal Integration

- Open the Terminal pane in the sidebar
- Configure an "On-boot command" in Settings to run when terminal loads
- Use the terminal alongside your notes for command-line workflows

## Troubleshooting

### Wiki links not working?
- Check that the target file exists (case-insensitive matching)
- Ensure the file has a `.md` extension
- Verify the file is in your vault folder (not outside)

### Images not showing?
- Use relative paths: `./assets/image.png`
- Supported formats: PNG, JPG, GIF
- Images must be in your vault or accessible via URL

### Tags not appearing?
- Tags must contain at least one letter
- Check that tags aren't inside URLs
- Tags are normalized to lowercase

### Template variables not substituting?
- Use double curly braces: `{{variable}}`
- Available variables: year, month, day, hour, minute, ampm, cursor
- Ensure templates are in the configured templates folder

## Advanced Features

### Git Sync

If your vault is a Git repository:

1. **Auto-save** - Automatically stage changes
2. **Auto-push** - Push to remote repository
3. **Conflict handling** - Visual indicators for merge conflicts

Configure in **Settings > Sync**.

### Gist Publishing

Publish notes to GitHub Gists:

1. Add your GitHub PAT in **Settings > Sync > GitHub PAT**
2. Right-click any note and select "Publish to Gist"
3. Choose public or private gist

### Split Panes

Work with multiple editor panes:

- **⌘D** - Split vertically
- **⇧⌘D** - Split horizontally
- **⌘⌥←→↑↓** - Switch between panes
- Each pane has independent tabs and history

### Customizable Sidebar

Drag and drop to customize your workspace:

1. Drag pane headers to reorder within a sidebar
2. Drag between left and right sidebars
3. Collapse panes you don't need
4. Add/remove panes from the "Add Pane" menu

Learn more:
- [User Guide](/) - Complete application guide
- [Keyboard Shortcuts](/) - All available shortcuts
- [GitHub Repository](https://github.com/dep/synapse) - Source code and issues
