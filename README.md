# Noted

Minimal macOS markdown editor with a built-in terminal, wiki links, quick open, and inline image previews.

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

## Notes

- The project uses `SwiftTerm` via Swift Package Manager.
- If you add new source files, regenerate the project with `xcodegen generate` before building.
