# Synapse

A minimal macOS markdown editor with a built-in terminal, wiki links, quick open, and inline image previews.

♥️ Built by nerds _for_ nerds.

<img width="1582" height="1035" alt="image" src="https://github.com/user-attachments/assets/f409440d-0d11-49c2-bb38-04ba16ce61d6" />

Docs: https://synapse-delta-nine.vercel.app/

## Project Structure

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

## Run In Xcode

If you prefer Xcode:

```bash
open macOS/Synapse.xcodeproj
```

Then select the `Synapse` scheme and press `Cmd-R`.

## Testing

Run tests from the command line:

```bash
cd macOS && xcodebuild test -project Synapse.xcodeproj -scheme Synapse -destination 'platform=macOS'
```

Or run tests in Xcode:

1. Open the project: `open macOS/Synapse.xcodeproj`
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
- `macOS/project.yml` must remain the source of truth for release signing settings; do not rely on Xcode-only UI changes because `xcodegen generate` will overwrite them

Create a signed Release archive:

```bash
cd macOS && xcodegen generate && \
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
