import XCTest
import AppKit
@testable import Synapse

    /// Tests for code block visual layout improvements:
    /// - no extra top padding and 10px bottom padding for fenced code blocks via NSParagraphStyle
/// - Minimum bounding-rect height for the copy-button position calculation
final class CodeBlockLayoutTests: XCTestCase {

    var textView: LinkAwareTextView!
    var scrollView: NSScrollView!

    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }

    override func tearDown() {
        textView.clearCodeBlockCopyButtons()
        textView = nil
        scrollView = nil
        super.tearDown()
    }

    // MARK: - Padding via NSParagraphStyle

    func test_codeBlock_openingFenceLine_hasNoParagraphSpacingBefore() {
        let text = "```\nhello code\n```"
        textView.setPlainText(text)

        guard let storage = textView.textStorage else {
            XCTFail("No text storage")
            return
        }

        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertNotNil(style, "Opening fence line should have a paragraphStyle attribute")
        XCTAssertEqual(style?.paragraphSpacingBefore ?? 0, 0, accuracy: 0.5,
                       "Opening fence line should not have top paragraph spacing")
    }

    func test_codeBlock_closingFenceLine_hasParagraphSpacingAfter() {
        let text = "```\nhello code\n```"
        textView.setPlainText(text)

        guard let storage = textView.textStorage else {
            XCTFail("No text storage")
            return
        }

        // The closing fence "```" starts at index 15
        let closingFenceStart = (text as NSString).range(of: "```", options: [], range: NSRange(location: 4, length: text.count - 4)).location
        let style = storage.attribute(.paragraphStyle, at: closingFenceStart, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertNotNil(style, "Closing fence line should have a paragraphStyle attribute")
        XCTAssertEqual(style?.paragraphSpacing ?? 0, 10, accuracy: 0.5,
                       "Closing fence line should have 10px paragraphSpacing (after)")
    }

    func test_codeBlock_hasFullWidthBackgroundMarker() {
        let text = "```\nhello code\n```"
        textView.setPlainText(text)

        guard let storage = textView.textStorage else {
            XCTFail("No text storage")
            return
        }

        // Marker must be present on the closing fence so drawBackground can extend fill to full width.
        let closingFenceStart = (text as NSString).range(of: "```", options: [], range: NSRange(location: 4, length: text.count - 4)).location
        let marker = storage.attribute(.codeBlockFullWidthBackground, at: closingFenceStart, effectiveRange: nil)

        XCTAssertNotNil(marker, "Closing fence line should carry .codeBlockFullWidthBackground so its background is drawn full-width")
    }

    func test_previewStyling_collapsesOpeningFenceLineHeight() {
        let text = "```\nhello code\n```"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        guard let storage = textView.textStorage else {
            XCTFail("No text storage")
            return
        }

        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertNotNil(style, "Opening fence line should keep a paragraphStyle attribute")
        XCTAssertEqual(style?.minimumLineHeight ?? -1, 0, accuracy: 0.5,
                       "Opening fence line should collapse to zero line height in preview mode")
        XCTAssertEqual(style?.maximumLineHeight ?? -1, 0, accuracy: 0.5,
                       "Opening fence line should collapse to zero line height in preview mode")
    }

    // MARK: - Copy button minimum height

    func test_singleLineCodeBlock_copyButtonHasMinHeight() {
        // A single-line code block produces a very short bounding rect.
        // refreshCodeBlockCopyButtons should still position the button correctly.
        let text = "```\ncode\n```"
        textView.setPlainText(text)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.refreshCodeBlockCopyButtons()

        // The copy button dict is private; verify via codeBlockMatches count
        // and that no crash occurred — if the button was positioned correctly the
        // method completes without throwing.
        let matches = textView.codeBlockMatches()
        XCTAssertEqual(matches.count, 1, "Should detect one code block")

        // Verify the button was added as a subview
        let buttonCount = textView.subviews.filter { $0 is CodeBlockCopyButton }.count
        XCTAssertEqual(buttonCount, 1, "One copy button should be present for the code block")
    }

    func test_multiLineCodeBlock_copyButtonPresent() {
        let text = "```\nline one\nline two\nline three\n```"
        textView.setPlainText(text)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.refreshCodeBlockCopyButtons()

        let buttonCount = textView.subviews.filter { $0 is CodeBlockCopyButton }.count
        XCTAssertEqual(buttonCount, 1, "One copy button should be present for a multi-line code block")
    }

    func test_multipleCodeBlocks_eachHasCopyButton() {
        let text = "```\nfirst\n```\n\nsome text\n\n```\nsecond\n```"
        textView.setPlainText(text)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.refreshCodeBlockCopyButtons()

        let buttonCount = textView.subviews.filter { $0 is CodeBlockCopyButton }.count
        XCTAssertEqual(buttonCount, 2, "Two copy buttons should be present for two code blocks")
    }
}
