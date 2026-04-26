import XCTest
@testable import Synapse

final class MarkdownPreviewSemanticHidingTests: XCTestCase {
    func test_make_hidesSharedSyntaxForBlocksAndInlineTokens() {
        let markdown = """
        # Heading
        > Quote
        [site](https://example.com) [[Note|Alias]] ![[Spec]]
        ```swift
        let value = 1
        ```
        """

        let hiding = MarkdownPreviewSemanticHiding.make(from: markdown, isEditable: false)
        let ns = markdown as NSString

        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "# ")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "> ")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "[")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "](https://example.com)")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "[[")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "Note|")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "]]", options: .backwards)))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "![[")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "```swift")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "```", options: .backwards)))
    }

    func test_make_hidesFrontmatterFencesOnlyInReadOnlyPreview() {
        let markdown = """
        ---
        title: Hello
        ---
        # Heading
        """

        let readOnly = MarkdownPreviewSemanticHiding.make(from: markdown, isEditable: false)
        let editable = MarkdownPreviewSemanticHiding.make(from: markdown, isEditable: true)
        let ns = markdown as NSString
        let fence = ns.range(of: "---")

        XCTAssertTrue(readOnly.hiddenRanges.contains(fence))
        XCTAssertFalse(editable.hiddenRanges.contains(fence))
    }

    func test_make_hidesCalloutMarkerButKeepsTitleVisible() {
        let markdown = "> [!NOTE] Remember this\n> Body"
        let hiding = MarkdownPreviewSemanticHiding.make(from: markdown, isEditable: true)
        let ns = markdown as NSString

        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "> ")))
        XCTAssertTrue(hiding.hiddenRanges.contains(ns.range(of: "[!NOTE]")))
        XCTAssertFalse(hiding.hiddenRanges.contains(ns.range(of: "Remember this")))
    }
}
