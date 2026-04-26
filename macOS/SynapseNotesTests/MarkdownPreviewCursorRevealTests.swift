import XCTest
@testable import Synapse

final class MarkdownPreviewCursorRevealTests: XCTestCase {
    func test_make_revealsMarkdownLinkWhenCursorInsideToken() {
        let markdown = "See [site](https://example.com) now"
        let ns = markdown as NSString
        let cursor = ns.range(of: "site").location + 1

        let reveal = MarkdownPreviewCursorReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertEqual(reveal.revealedRanges, [ns.range(of: "[site](https://example.com)")])
    }

    func test_make_revealsWikilinkWhenCursorInsideAlias() {
        let markdown = "See [[Target|Shown]] now"
        let ns = markdown as NSString
        let cursor = ns.range(of: "Shown").location + 2

        let reveal = MarkdownPreviewCursorReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertEqual(reveal.revealedRanges, [ns.range(of: "[[Target|Shown]]")])
    }

    func test_make_revealsEmbedWhenCursorInsideToken() {
        let markdown = "See ![[Spec]] now"
        let ns = markdown as NSString
        let cursor = ns.range(of: "Spec").location + 1

        let reveal = MarkdownPreviewCursorReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertEqual(reveal.revealedRanges, [ns.range(of: "![[Spec]]")])
    }

    func test_make_doesNotRevealWhenCursorOutsideToken() {
        let markdown = "See [site](https://example.com) now"

        let reveal = MarkdownPreviewCursorReveal.make(from: markdown, cursorLocation: 1, isEditable: true)

        XCTAssertTrue(reveal.revealedRanges.isEmpty)
    }

    func test_make_revealsMarkdownImageWhenCursorInsideCaption() {
        let markdown = "See ![diagram](https://example.com/diagram.png) now"
        let ns = markdown as NSString
        let cursor = ns.range(of: "diagram").location + 2

        let reveal = MarkdownPreviewCursorReveal.make(from: markdown, cursorLocation: cursor, isEditable: true)

        XCTAssertEqual(reveal.revealedRanges, [ns.range(of: "![diagram](https://example.com/diagram.png)")])
    }
}
