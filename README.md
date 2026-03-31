# Synapse

A minimal macOS markdown editor with a built-in terminal, wiki links, quick open, and inline image previews.

♥️ Built with love by nerds _for_ nerds.

<img width="1569" height="1035" alt="image" src="https://github.com/user-attachments/assets/35484b4b-d0d0-4c4c-a4ec-79bdcd935978" />

* Download: https://github.com/dep/synapse/releases/latest
* Docs: https://synapse-delta-nine.vercel.app/

## Developer stuff

### Product Structure

```
synapse/
├── macOS/              # macOS app (current)
│   ├── Synapse/        # Source files
│   ├── SynapseTests/   # Test suite
│   ├── Synapse.xcodeproj
│   └── project.yml
├── marketing-site/     # Documentation website
└── ...                 # Shared resources
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
cd macOS && xcodebuild -project "Synapse.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build
```

3. Launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/Synapse-*/Build/Products/Debug/Synapse.app
```

Or do all three steps in one shot:

```bash
cd macOS && xcodegen generate && xcodebuild -project "Synapse.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build && open ~/Library/Developer/Xcode/DerivedData/Synapse-*/Build/Products/Debug/Synapse.app
```

The app is built into Xcode DerivedData under the Debug products folder.

### Run In Xcode

If you prefer Xcode:

```bash
open macOS/Synapse.xcodeproj
```

Then select the `Synapse` scheme and press `Cmd-R`.

### Testing

Run tests from the command line:

```bash
cd macOS && xcodebuild test -project Synapse.xcodeproj -scheme Synapse -destination 'platform=macOS'
```

Or run tests in Xcode:

1. Open the project: `open macOS/Synapse.xcodeproj`
2. Select the `Synapse` scheme
3. Press `Cmd-U` to run all tests

## License

MIT License — see [LICENSE](LICENSE) for details.
