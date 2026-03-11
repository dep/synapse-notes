# Noted

Minimal macOS markdown editor with a built-in terminal, wiki links, quick open, and inline image previews.

<img width="1582" height="1035" alt="image" src="https://github.com/user-attachments/assets/116c7555-0796-4aa7-96e3-fcdfb13ca152" />


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
xcodebuild -project "Noted.xcodeproj" -scheme "Noted" -destination "platform=macOS" build
```

3. Launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/Noted-*/Build/Products/Debug/Noted.app
```

Or do all three steps in one shot:

```bash
xcodegen generate && xcodebuild -project "Noted.xcodeproj" -scheme "Noted" -destination "platform=macOS" build && open ~/Library/Developer/Xcode/DerivedData/Noted-*/Build/Products/Debug/Noted.app
```

The app is built into Xcode DerivedData under the Debug products folder.

## Run In Xcode

If you prefer Xcode:

```bash
open Noted.xcodeproj
```

Then select the `Noted` scheme and press `Cmd-R`.

## Testing

Run tests from the command line:

```bash
xcodebuild test -scheme Noted -destination 'platform=macOS'
```

Or run tests in Xcode:

1. Open the project: `open Noted.xcodeproj`
2. Select the `Noted` scheme
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
- A configured notarization profile for `notarytool` (example: `noted-notary`)
- `project.yml` must remain the source of truth for release signing settings; do not rely on Xcode-only UI changes because `xcodegen generate` will overwrite them

Create a signed Release archive:

```bash
xcodegen generate && \
xcodebuild archive \
  -project "Noted.xcodeproj" \
  -scheme "Noted" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/Noted.xcarchive"
```

Package the app for notarization:

```bash
ditto -c -k --keepParent \
  "/tmp/Noted.xcarchive/Products/Applications/Noted.app" \
  "/tmp/Noted.zip"
```

Submit, wait, and staple:

```bash
xcrun notarytool submit "/tmp/Noted.zip" --keychain-profile "noted-notary" --wait && \
xcrun stapler staple "/tmp/Noted.xcarchive/Products/Applications/Noted.app" && \
spctl --assess --type execute --verbose=4 "/tmp/Noted.xcarchive/Products/Applications/Noted.app"
```

Expected successful validation output includes:

- `accepted`
- `source=Notarized Developer ID`

Artifacts:

- notarized app: `/tmp/Noted.xcarchive/Products/Applications/Noted.app`
- shareable zip: `/tmp/Noted.zip`

## Notes

- The project uses `SwiftTerm` via Swift Package Manager.
- If you add new source files, regenerate the project with `xcodegen generate` before building.
