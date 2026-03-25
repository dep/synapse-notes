import XCTest
@testable import Synapse

final class MarkdownPreviewRendererTests: XCTestCase {
    private var renderer: MarkdownPreviewRenderer!

    override func setUp() {
        super.setUp()
        renderer = MarkdownPreviewRenderer()
    }

    override func tearDown() {
        renderer = nil
        super.tearDown()
    }

    func test_renderBody_rendersHeadingMarkdownLinkWikiLinkAndEmbedFromSharedModel() {
        let markdown = """
        # Title

        Read [docs](https://example.com) and [[Roadmap|Plan]] plus ![[Spec]].
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">docs</a>"))
        XCTAssertTrue(html.contains("<a href=\"wikilink://Roadmap\" class=\"wikilink\">Plan</a>"))
        XCTAssertTrue(html.contains("<span class=\"embed\">Spec</span>"))
    }

    func test_renderBody_rendersBlockquoteAndFencedCodeBlock() {
        let markdown = """
        > Quoted line

        ```swift
        let answer = 42
        ```
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<blockquote>Quoted line</blockquote>"))
        XCTAssertTrue(html.contains("<pre><code class=\"hljs language-swift\">let answer = 42</code></pre>"))
    }

    func test_renderBody_rendersCalloutBlockquoteWithClass() {
        let markdown = "> [!NOTE] Remember this\n> Body line"

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<blockquote class=\"callout callout-note\">"))
        XCTAssertTrue(html.contains("callout-title\">Remember this</div>"))
        XCTAssertTrue(html.contains("callout-body\">Body line</div>"))
    }

    func test_renderBody_rendersValidPipeTableAsTable() {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | One | 1 |
        | Two | 2 |
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>Two</td>"))
        XCTAssertTrue(html.contains("<td>2</td>"))
    }

    func test_renderBody_keepsMalformedTableAsPlainParagraphs() {
        let markdown = """
        | Name | Value |
        not a separator row
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<table>"))
        XCTAssertTrue(html.contains("<p>| Name | Value |</p>"))
        XCTAssertTrue(html.contains("<p>not a separator row</p>"))
    }

    func test_renderBody_rendersHighlightSyntaxAsMarkElement() {
        let markdown = "This is ==highlighted text== in a paragraph."

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<mark>highlighted text</mark>"))
    }

    func test_renderBody_rendersHighlightWithOtherInlineFormatting() {
        let markdown = "**==bold and highlighted==** and ==highlighted with *italic* inside=="

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<mark>bold and highlighted</mark>"))
        XCTAssertTrue(html.contains("<mark>highlighted with <em>italic</em> inside</mark>"))
    }

    func test_renderBody_ignoresEmptyHighlight() {
        let markdown = "This ==== is not a highlight."

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<mark>"))
        XCTAssertTrue(html.contains("<p>This ==== is not a highlight.</p>"))
    }

    func test_renderBody_rendersUnclosedHighlightAsLiteral() {
        let markdown = "This ==is not closed"

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<mark>"))
        XCTAssertTrue(html.contains("==is not closed"))
    }
}
