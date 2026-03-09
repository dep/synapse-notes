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

## Notes

- The project uses `SwiftTerm` via Swift Package Manager.
- If you add new source files, regenerate the project with `xcodegen generate` before building.
