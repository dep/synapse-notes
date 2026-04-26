# Synapse Notes

Synapse Notes is a powerful Markdown-based knowledge management application exclusively built for macOS using SwiftUI. It's your second brain, backed by YOUR Git repository, and is deeply customizable.

♥️ Built with love by nerds _for_ nerds.

### [Download now](https://github.com/dep/synapse/releases/latest) | [Read the docs](https://synapsenotes.app/)

<img width="1569" height="1035" alt="image" src="https://github.com/user-attachments/assets/35484b4b-d0d0-4c4c-a4ec-79bdcd935978" />

## Developer stuff

### Product Structure

```
synapse-notes/
├── macOS/                    # macOS app (current)
│   ├── SynapseNotes/         # Source files
│   ├── SynapseNotesTests/    # Test suite
│   ├── Synapse Notes.xcodeproj
│   └── project.yml
├── marketing-site/           # Documentation website
└── ...                       # Shared resources
```

### Requirements

- macOS 14+
- Xcode 16+
- Homebrew
- `xcodegen`

Install `xcodegen` if needed:

```bash
brew install xcodegen
```

### Build And Run

Preferred: run it entirely from the CLI.

1. Generate the Xcode project:

```bash
cd macOS && xcodegen generate
```

2. Build the app:

```bash
cd macOS && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build
```

3. Launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/Synapse_Notes-*/Build/Products/Debug/"Synapse Notes.app"
```

Or do all three steps in one shot:

```bash
cd macOS && xcodegen generate && xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build && open ~/Library/Developer/Xcode/DerivedData/Synapse_Notes-*/Build/Products/Debug/"Synapse Notes.app"
```

The app is built into Xcode DerivedData under the Debug products folder.

### Run In Xcode

If you prefer Xcode:

```bash
open "macOS/Synapse Notes.xcodeproj"
```

Then select the `Synapse` scheme and press `Cmd-R`.

### Testing

Run tests from the command line:

```bash
cd macOS && xcodebuild test -project "Synapse Notes.xcodeproj" -scheme Synapse -destination 'platform=macOS'
```

Or run tests in Xcode:

1. Open the project: `open "macOS/Synapse Notes.xcodeproj"`
2. Select the `Synapse` scheme
3. Press `Cmd-U` to run all tests

## Support

If Synapse Notes saves you money on a notes app subscription or just sparks a little joy, a coffee goes a long way. ☕

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/dnnypck)

## License

MIT License — see [LICENSE](LICENSE) for details.
