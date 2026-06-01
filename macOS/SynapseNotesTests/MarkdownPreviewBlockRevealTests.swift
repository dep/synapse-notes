import XCTest
@testable import Synapse

final class MarkdownPreviewBlockRevealTests: XCTestCase {
    func test_make_revealsHeadingPrefixWhenCursorOnHeading() {
        let markdown = "# Title\n\nBody text here"
        let ns = markdown as NSString
        let cursor = ns.range(of: "Title").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "# ")))
    }

    func test_make_revealsBoldDelimitersWithinWrappedParagraph() {
        let markdown = "Some text with **bold phrase** in the middle of a long paragraph."
        let ns = markdown as NSString
        let cursor = ns.range(of: "bold phrase").location + 2

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        // Both ** delimiters revealed.
        XCTAssertEqual(reveal.revealedRanges.filter { ns.substring(with: $0) == "**" }.count, 2)
    }

    func test_make_revealsBothFencesWhenCursorInsideCodeBlock() {
        let markdown = "```swift\nlet value = 1\nlet other = 2\n```"
        let ns = markdown as NSString
        let cursor = ns.range(of: "let value").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "```swift")))
        XCTAssertTrue(reveal.revealedRanges.contains(ns.range(of: "```", options: .backwards)))
    }

    func test_make_revealsNothingWhenCursorOnBlankLineBetweenBlocks() {
        let markdown = "# Title\n\nBody"
        let ns = markdown as NSString
        // The blank line is the \n\n gap; cursor on the empty second line.
        let cursor = ns.range(of: "\n\n").location + 1

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.isEmpty)
    }

    func test_make_revealsNothingWhenNotEditable() {
        let markdown = "# Title"
        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: 2, isEditable: false)
        XCTAssertTrue(reveal.revealedRanges.isEmpty)
    }

    func test_make_doesNotRevealDelimitersOutsideCaretBlock() {
        let markdown = "**first** bold\n\n**second** bold"
        let ns = markdown as NSString
        let cursor = ns.range(of: "first").location

        let reveal = MarkdownPreviewBlockReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        // No revealed range may fall in the second block (after the blank line).
        let secondBlockStart = ns.range(of: "second").location - 2
        XCTAssertFalse(reveal.revealedRanges.contains { $0.location >= secondBlockStart })
    }
}
