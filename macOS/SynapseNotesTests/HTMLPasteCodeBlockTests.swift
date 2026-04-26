import XCTest
import AppKit
@testable import Synapse

/// Tests that HTML paste is suppressed when the cursor is inside a fenced code block.
final class HTMLPasteCodeBlockTests: XCTestCase {

    private var tempDir: URL!
    private var testFile: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testFile = tempDir.appendingPathComponent("test.md")
        try! "".write(to: testFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        testFile = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTextView(content: String, cursorAt location: Int) -> LinkAwareTextView {
        let tv = LinkAwareTextView()
        tv.currentFileURL = testFile
        tv.string = content
        tv.setSelectedRange(NSRange(location: location, length: 0))
        return tv
    }

    private func htmlPasteboard(_ html: String) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("HTMLPasteCodeBlockTests-\(UUID())"))
        pb.clearContents()
        pb.setString(html, forType: .string)
        return pb
    }

    // MARK: - Should NOT convert inside code blocks

    /// Cursor is on the opening fence line: ``` <cursor>
    func test_pasteOnOpeningFenceLine_retainsHTML() {
        let content = "```"
        // cursor at end of the ``` line
        let tv = makeTextView(content: content, cursorAt: 3)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertFalse(handled, "Should not convert HTML when cursor is on opening fence line")
    }

    /// Cursor is on a blank line immediately after the opening fence: ```\n<cursor>
    func test_pasteAfterOpeningFenceNoClosing_retainsHTML() {
        let content = "```\n"
        let tv = makeTextView(content: content, cursorAt: 4)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertFalse(handled, "Should not convert HTML inside unclosed code block")
    }

    /// Complete block: ```\nsome code\n``` — cursor inside the content.
    func test_pasteCursorInsideCompleteBlock_retainsHTML() {
        let content = "```\nsome code\n```"
        // cursor in "some code" region
        let tv = makeTextView(content: content, cursorAt: 7)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertFalse(handled, "Should not convert HTML inside a complete fenced code block")
    }

    /// Complete block with language tag: ```html\ncontent\n```
    func test_pasteCursorInsideLanguageTaggedBlock_retainsHTML() {
        let content = "```html\n<ul><li>existing</li></ul>\n```"
        let tv = makeTextView(content: content, cursorAt: 10)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertFalse(handled, "Should not convert HTML inside a language-tagged code block")
    }

    // MARK: - SHOULD convert outside code blocks

    /// Cursor is before any code block — normal HTML conversion.
    func test_pasteBeforeCodeBlock_convertsHTML() {
        let content = "Some text\n\n```\ncode\n```"
        // cursor at start
        let tv = makeTextView(content: content, cursorAt: 0)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertTrue(handled, "Should convert HTML when cursor is before any code block")
    }

    /// Cursor is after a closed code block — normal HTML conversion.
    func test_pasteAfterClosedCodeBlock_convertsHTML() {
        let content = "```\ncode\n```\n\nAfter block"
        // cursor at end
        let tv = makeTextView(content: content, cursorAt: content.count)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertTrue(handled, "Should convert HTML when cursor is after a closed code block")
    }

    /// No code block at all — normal conversion.
    func test_pasteWithNoCodeBlock_convertsHTML() {
        let content = "Just some markdown text"
        let tv = makeTextView(content: content, cursorAt: content.count)
        let pb = htmlPasteboard("<ul><li>Item</li></ul>")

        let handled = tv.handleHTMLPaste(from: pb)

        XCTAssertTrue(handled, "Should convert HTML when there is no code block")
    }
}
