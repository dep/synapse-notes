import XCTest
@testable import Synapse

/// Tests for the sidebar drag-and-drop encode/decode helpers in ContentView.
///
/// `sidebarItemToken(for:)` encodes a `SidebarPaneItem` as a prefixed base64 JSON token
/// so it can be transferred via `NSItemProvider` as plain text.  `sidebarItem(from:)` is
/// the inverse — it decodes the token back into a `SidebarPaneItem`.
///
/// `extractSidebarFileURL(from:)` extracts a file URL from the various types that
/// `NSItemProvider` may hand back: raw `Data`, `URL`, `NSURL`, or a `String` (file://-
/// prefixed URL or an absolute path with optional tilde expansion).
///
/// These functions power the "drag files / panes to sidebar" feature.  A regression in
/// any of them silently breaks sidebar reordering with no obvious error message.
final class SidebarDragDropTests: XCTestCase {

    // MARK: - sidebarItemToken round-trip (builtIn panes)

    func test_sidebarItemToken_builtInFiles_hasExpectedPrefix() {
        let item = SidebarPaneItem.builtIn(.files)
        let token = sidebarItemToken(for: item)
        XCTAssertTrue(token.hasPrefix(sidebarItemTokenPrefix),
                      "Token must begin with the sentinel prefix so decoders can identify it")
    }

    func test_sidebarItemToken_roundTrip_builtInFiles() {
        let original = SidebarPaneItem.builtIn(.files)
        let token = sidebarItemToken(for: original)
        let decoded = sidebarItem(from: token)
        XCTAssertEqual(decoded, original, "Round-trip encode→decode must reproduce the original item")
    }

    func test_sidebarItemToken_roundTrip_builtInTags() {
        let original = SidebarPaneItem.builtIn(.tags)
        let decoded = sidebarItem(from: sidebarItemToken(for: original))
        XCTAssertEqual(decoded, original)
    }

    func test_sidebarItemToken_roundTrip_builtInGraph() {
        let original = SidebarPaneItem.builtIn(.graph)
        let decoded = sidebarItem(from: sidebarItemToken(for: original))
        XCTAssertEqual(decoded, original)
    }

    func test_sidebarItemToken_roundTrip_builtInTerminal() {
        let original = SidebarPaneItem.builtIn(.terminal)
        let decoded = sidebarItem(from: sidebarItemToken(for: original))
        XCTAssertEqual(decoded, original)
    }

    func test_sidebarItemToken_roundTrip_builtInBrowser() {
        let original = SidebarPaneItem.builtIn(.browser)
        let decoded = sidebarItem(from: sidebarItemToken(for: original))
        XCTAssertEqual(decoded, original)
    }

    func test_sidebarItemToken_roundTrip_notePane() {
        let notePane = SidebarNotePane(id: UUID(), path: "/tmp/my-note.md")
        let original = SidebarPaneItem.note(notePane)
        let decoded = sidebarItem(from: sidebarItemToken(for: original))
        XCTAssertEqual(decoded, original, "Note pane round-trip must preserve id and path")
    }

    func test_sidebarItemToken_differentItems_produceDifferentTokens() {
        let tokenFiles = sidebarItemToken(for: .builtIn(.files))
        let tokenTags  = sidebarItemToken(for: .builtIn(.tags))
        XCTAssertNotEqual(tokenFiles, tokenTags,
                          "Different items must produce distinct tokens")
    }

    // MARK: - sidebarItem(from:) invalid input

    func test_sidebarItem_fromEmptyString_returnsNil() {
        XCTAssertNil(sidebarItem(from: ""), "Empty string is not a valid token")
    }

    func test_sidebarItem_fromArbitraryString_returnsNil() {
        XCTAssertNil(sidebarItem(from: "files"),
                     "A bare SidebarPane rawValue is not a sidebar item token")
    }

    func test_sidebarItem_fromPrefixWithGarbage_returnsNil() {
        let garbage = sidebarItemTokenPrefix + "!!! not base64 !!!"
        XCTAssertNil(sidebarItem(from: garbage),
                     "Prefix + invalid base64 must not crash and must return nil")
    }

    func test_sidebarItem_fromPrefixWithValidBase64ButInvalidJSON_returnsNil() {
        let validBase64OfGarbage = "aGVsbG8="  // "hello" in base64
        let token = sidebarItemTokenPrefix + validBase64OfGarbage
        XCTAssertNil(sidebarItem(from: token),
                     "Valid base64 that isn't a SidebarPaneItem JSON must return nil")
    }
}

// MARK: - extractSidebarFileURL tests

final class SidebarFileURLExtractionTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Data input (file URL serialised by NSItemProvider)

    func test_extractSidebarFileURL_fromDataRepresentation_returnsURL() {
        let original = tempDir.appendingPathComponent("note.md")
        let data = original.dataRepresentation
        let result = extractSidebarFileURL(from: data)
        XCTAssertEqual(result?.standardizedFileURL, original.standardizedFileURL,
                       "Data representation should be decoded back to the same URL")
    }

    // MARK: - URL input

    func test_extractSidebarFileURL_fromURL_returnsStandardizedURL() {
        let original = tempDir.appendingPathComponent("doc.txt")
        let result = extractSidebarFileURL(from: original)
        XCTAssertEqual(result, original.standardizedFileURL)
    }

    func test_extractSidebarFileURL_fromURL_standardizes() {
        let unstandardized = URL(fileURLWithPath: tempDir.path + "/./sub/../note.md")
        let result = extractSidebarFileURL(from: unstandardized)
        XCTAssertEqual(result, unstandardized.standardizedFileURL)
    }

    // MARK: - NSURL input

    func test_extractSidebarFileURL_fromNSURL_returnsURL() {
        let original = tempDir.appendingPathComponent("file.md")
        let nsURL = original as NSURL
        let result = extractSidebarFileURL(from: nsURL)
        XCTAssertEqual(result, original.standardizedFileURL)
    }

    // MARK: - String input — file:// prefixed

    func test_extractSidebarFileURL_fromFileURLString_returnsURL() {
        let path = tempDir.appendingPathComponent("note.md").path
        let urlString = "file://" + path
        let result = extractSidebarFileURL(from: urlString)
        XCTAssertNotNil(result, "file:// string should be resolved to a URL")
        XCTAssertEqual(result?.path, path)
    }

    // MARK: - String input — absolute path

    func test_extractSidebarFileURL_fromAbsolutePath_returnsURL() {
        let path = tempDir.appendingPathComponent("notes/readme.md").path
        let result = extractSidebarFileURL(from: path)
        XCTAssertNotNil(result, "An absolute path string should be resolved to a URL")
        XCTAssertTrue(result!.path.hasSuffix("readme.md"))
    }

    // MARK: - Nil / unsupported input

    func test_extractSidebarFileURL_fromNil_returnsNil() {
        XCTAssertNil(extractSidebarFileURL(from: nil),
                     "nil input must return nil without crashing")
    }

    func test_extractSidebarFileURL_fromNSNumber_returnsNil() {
        XCTAssertNil(extractSidebarFileURL(from: NSNumber(value: 42)),
                     "Unsupported type must return nil")
    }

    func test_extractSidebarFileURL_fromRelativePath_returnsNil() {
        XCTAssertNil(extractSidebarFileURL(from: "relative/path/note.md"),
                     "Relative path without a leading slash must return nil")
    }

    func test_extractSidebarFileURL_fromHTTPString_returnsNil() {
        XCTAssertNil(extractSidebarFileURL(from: "https://example.com/note.md"),
                     "Non-file URL string must return nil")
    }
}
