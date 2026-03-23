import XCTest
import AppKit
@testable import Synapse

/// Tests for applyPreviewStyling() — verifies that markdown syntax tokens are hidden
/// and that fenced code blocks only hide fences for complete (matched) pairs.
final class PreviewModeTests: XCTestCase {

    var textView: LinkAwareTextView!

    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView()
        textView.isEditable = false
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    override func tearDown() {
        textView = nil
        super.tearDown()
    }

    /// Returns true if the character at `index` in the text storage has a clear/hidden foreground color.
    private func isHidden(at index: Int) -> Bool {
        guard let storage = textView.textStorage, index < storage.length else { return false }
        if let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor {
            return color.alphaComponent < 0.01
        }
        // Font size near-zero is the other hide mechanism
        if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
            return font.pointSize < 0.1
        }
        return false
    }

    /// Returns true if every character in `range` of the text storage is hidden.
    private func allHidden(in range: NSRange) -> Bool {
        guard let storage = textView.textStorage else { return false }
        for i in range.location ..< (range.location + range.length) {
            guard i < storage.length else { return false }
            if !isHidden(at: i) { return false }
        }
        return true
    }

    /// Returns true if at least one character in `range` is NOT hidden.
    private func anyVisible(in range: NSRange) -> Bool {
        guard let storage = textView.textStorage else { return false }
        for i in range.location ..< (range.location + range.length) {
            guard i < storage.length else { continue }
            if !isHidden(at: i) { return true }
        }
        return false
    }

    // MARK: - Syntax token hiding

    func test_headingHash_isHiddenInPreview() {
        textView.setPlainText("# Heading One")
        textView.applyPreviewStyling()

        // The "# " prefix (first 2 chars) should be hidden
        XCTAssertTrue(allHidden(in: NSRange(location: 0, length: 2)), "ATX heading '# ' prefix should be hidden in preview")
        // The heading text itself should be visible
        XCTAssertTrue(anyVisible(in: NSRange(location: 2, length: 11)), "Heading text should remain visible in preview")
    }

    func test_boldDelimiters_areHiddenInPreview() {
        let text = "Hello **world** end"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        let ns = text as NSString
        // "**" before "world" at index 6
        let openRange = NSRange(location: 6, length: 2)
        // "**" after "world" at index 13
        let closeRange = NSRange(location: 13, length: 2)

        XCTAssertTrue(allHidden(in: openRange), "Opening ** should be hidden in preview")
        XCTAssertTrue(allHidden(in: closeRange), "Closing ** should be hidden in preview")
        // "world" (index 8–12) should be visible
        XCTAssertTrue(anyVisible(in: NSRange(location: 8, length: 5)), "Bold content should remain visible")
    }

    func test_inlineCodeBackticks_areHiddenInPreview() {
        let text = "Use `func()` here"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        let ns = text as NSString
        // Opening backtick at index 4
        XCTAssertTrue(isHidden(at: 4), "Opening backtick should be hidden in preview")
        // Closing backtick at index 11
        XCTAssertTrue(isHidden(at: 11), "Closing backtick should be hidden in preview")
        // "func()" content should be visible
        XCTAssertTrue(anyVisible(in: NSRange(location: 5, length: 6)), "Inline code content should remain visible")
    }

    func test_blockquotePrefix_isHiddenInPreview() {
        let text = "> A blockquote"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        // "> " prefix (2 chars)
        XCTAssertTrue(allHidden(in: NSRange(location: 0, length: 2)), "Blockquote '> ' prefix should be hidden")
        XCTAssertTrue(anyVisible(in: NSRange(location: 2, length: 12)), "Blockquote content should remain visible")
    }

    // MARK: - Fenced code block fence visibility

    func test_completeFencePair_bothFencesAreHidden() {
        let text = "```\nhello code\n```"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        // Opening fence "```" at index 0–2
        XCTAssertTrue(allHidden(in: NSRange(location: 0, length: 3)), "Opening ``` of a complete pair should be hidden")
        // Closing fence "```" at index 15–17
        let closingFenceStart = (text as NSString).range(of: "```", options: [], range: NSRange(location: 4, length: text.count - 4)).location
        XCTAssertTrue(allHidden(in: NSRange(location: closingFenceStart, length: 3)), "Closing ``` of a complete pair should be hidden")
    }

    func test_unclosedFence_remainsVisible() {
        let text = "```\nhello code\nno closing fence"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        // Opening fence "```" at index 0 should NOT be hidden (no matching close)
        XCTAssertFalse(allHidden(in: NSRange(location: 0, length: 3)), "Unclosed ``` should remain visible so the user knows it is open")
    }

    func test_twoPairs_allFencesHidden() {
        let text = "```\nfirst block\n```\nsome text\n```\nsecond block\n```"
        textView.setPlainText(text)
        textView.applyPreviewStyling()

        // Both opening fences should be hidden
        // First opening at 0
        XCTAssertTrue(allHidden(in: NSRange(location: 0, length: 3)), "First opening fence should be hidden")
        // Second opening — find it
        let ns = text as NSString
        let secondOpenRange = ns.range(of: "```", options: [], range: NSRange(location: 20, length: ns.length - 20))
        XCTAssertTrue(allHidden(in: NSRange(location: secondOpenRange.location, length: 3)), "Second opening fence should be hidden")
    }

    func test_reapplyingMarkdownStyling_afterPreviewRequestsRedraw() {
        let redrawTrackingTextView = RedrawTrackingTextView()
        redrawTrackingTextView.isEditable = false
        redrawTrackingTextView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        redrawTrackingTextView.setPlainText("# Heading\n\n**bold**")
        redrawTrackingTextView.applyPreviewStyling()
        redrawTrackingTextView.setNeedsDisplayCallCount = 0

        redrawTrackingTextView.applyMarkdownStyling()

        XCTAssertGreaterThan(redrawTrackingTextView.setNeedsDisplayCallCount, 0, "Restoring markdown styling should request a redraw immediately")
    }

    func test_refreshEditorForHideMarkdownToggle_restoresVisibleMarkdownWithoutTyping() {
        let redrawTrackingTextView = RedrawTrackingTextView()
        redrawTrackingTextView.isEditable = true
        redrawTrackingTextView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        redrawTrackingTextView.setPlainText("# Heading")
        redrawTrackingTextView.applyPreviewStyling()
        XCTAssertTrue(storageIsHidden(in: redrawTrackingTextView, at: 0), "Precondition: preview mode hides markdown syntax")

        redrawTrackingTextView.setNeedsDisplayCallCount = 0
        refreshEditorForHideMarkdownToggle(redrawTrackingTextView, hideMarkdown: false)

        XCTAssertFalse(storageIsHidden(in: redrawTrackingTextView, at: 0), "Toggling hide-markdown off should restore markdown immediately")
        XCTAssertGreaterThan(redrawTrackingTextView.setNeedsDisplayCallCount, 0, "Refreshing after Cmd-E should request a redraw")
    }

    // MARK: - Table Rendering Tests
    // Note: Tables now show raw markdown in all modes - this is intentional behavior
    // The preview mode uses a WebView which renders tables as HTML with proper formatting
    // In edit/hide-markdown mode, tables show raw markdown so users can edit them

    func test_tablePipes_areVisibleInEditMode() {
        let tableText = "| Time | Event |\n|------|-------|\n| 9:00 | Meeting |"
        textView.setPlainText(tableText)
        textView.isEditable = true
        textView.applyPreviewStyling()

        let ns = tableText as NSString
        // First pipe at index 0 - should be VISIBLE in edit mode (not hidden)
        XCTAssertFalse(allHidden(in: NSRange(location: 0, length: 1)), "Opening pipe should be visible in edit mode")
        // Cell content "Time" should also be visible
        let timeRange = ns.range(of: "Time")
        XCTAssertTrue(anyVisible(in: timeRange), "Cell content 'Time' should remain visible")
    }

    func test_tableSeparatorRow_isVisibleInEditMode() {
        let tableText = "| Time | Event |\n|------|-------|\n| 9:00 | Meeting |"
        textView.setPlainText(tableText)
        textView.isEditable = true
        textView.applyPreviewStyling()

        let ns = tableText as NSString
        // Separator row should be VISIBLE in edit mode (not hidden)
        let separatorRange = ns.range(of: "|------|-------|")
        XCTAssertFalse(allHidden(in: separatorRange), "Table separator row should be visible in edit mode")
    }

    func test_tableCellContent_isVisibleInEditMode() {
        let tableText = "| Time | Event |\n|------|-------|\n| 9:00 | Meeting |"
        textView.setPlainText(tableText)
        textView.isEditable = true
        textView.applyPreviewStyling()

        let ns = tableText as NSString
        // Cell content should be visible
        let meetingRange = ns.range(of: "Meeting")
        XCTAssertTrue(anyVisible(in: meetingRange), "Cell content 'Meeting' should be visible")
    }

    func test_tableRawMarkdown_revealedWhenCursorInside() {
        let tableText = "| Time | Event |\n|------|-------|\n| 9:00 | Meeting |"
        textView.setPlainText(tableText)
        textView.isEditable = true

        // Position cursor inside the table (after "Time")
        let ns = tableText as NSString
        let timeRange = ns.range(of: "Time")
        let cursorPosition = timeRange.location + 2 // In middle of "Time"
        textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

        // Apply preview styling (simulating hide-markdown mode)
        textView.applyPreviewStyling()

        // The pipe near the cursor should be visible (tables show raw markdown in edit mode)
        let pipeBeforeTime = timeRange.location - 2
        if pipeBeforeTime >= 0 {
            XCTAssertFalse(allHidden(in: NSRange(location: pipeBeforeTime, length: 1)), "Table syntax should be visible when cursor is inside")
        }
    }

    func test_tableRawMarkdown_visibleWhenCursorOutside() {
        let tableText = "Some text before\n\n| Time | Event |\n|------|-------|\n| 9:00 | Meeting |\n\nSome text after"
        textView.setPlainText(tableText)
        textView.isEditable = true

        // Position cursor outside the table (in "Some text before")
        let ns = tableText as NSString
        let beforeRange = ns.range(of: "Some text before")
        let cursorPosition = beforeRange.location + 5
        textView.setSelectedRange(NSRange(location: cursorPosition, length: 0))

        // Apply preview styling
        textView.applyPreviewStyling()

        // The table pipes should be VISIBLE (tables show raw markdown in edit mode)
        let firstPipeInTable = ns.range(of: "| Time").location
        XCTAssertFalse(isHidden(at: firstPipeInTable), "Table syntax should be visible in edit mode")
    }

    func test_table_rendersWithRawMarkdownInEditMode() {
        let tableText = "| Time | Event |\n|------|-------|\n| 9:00 | Meeting |"
        textView.setPlainText(tableText)
        textView.isEditable = true

        // Simulate hide-markdown-while-editing mode
        textView.applyPreviewStyling()

        // Tables should show raw markdown (pipes visible)
        XCTAssertFalse(isHidden(at: 0), "Opening pipe should be visible in editable preview mode")

        let ns = tableText as NSString
        let meetingRange = ns.range(of: "Meeting")
        XCTAssertTrue(anyVisible(in: meetingRange), "Cell content should be visible")
    }
}

private final class RedrawTrackingTextView: LinkAwareTextView {
    var setNeedsDisplayCallCount = 0

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        setNeedsDisplayCallCount += 1
        super.setNeedsDisplay(invalidRect)
    }
}

private func storageIsHidden(in textView: LinkAwareTextView, at index: Int) -> Bool {
    guard let storage = textView.textStorage, index < storage.length else { return false }
    if let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor {
        return color.alphaComponent < 0.01
    }
    if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
        return font.pointSize < 0.1
    }
    return false
}
