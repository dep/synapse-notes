import XCTest
@testable import Synapse

final class MarkdownDocumentParserTests: XCTestCase {
    private var parser: MarkdownDocumentParser!

    override func setUp() {
        super.setUp()
        parser = MarkdownDocumentParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    func test_parse_isDeterministicAndPreservesSource() {
        let markdown = """
        # Title

        A paragraph with [docs](https://example.com).

        - [ ] Ship phase A
        """

        let first = parser.parse(markdown)
        let second = parser.parse(markdown)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.source, markdown)
        XCTAssertEqual(
            first.blocks.map(\.kind),
            [
                .heading(level: 1),
                .paragraph,
                .taskListItem(indent: 0, isChecked: false),
            ]
        )
    }

    func test_parse_frontmatter_createsDedicatedBlockWithInnerContentRange() {
        let markdown = """
        ---
        title: Hello
        layout: note
        ---
        # Heading
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .frontmatter)
        XCTAssertEqual(substring(markdown, range: document.blocks[0].range), "---\ntitle: Hello\nlayout: note\n---")
        XCTAssertEqual(substring(markdown, range: document.blocks[0].contentRange), "title: Hello\nlayout: note\n")
        XCTAssertEqual(document.blocks[1].kind, .heading(level: 1))
    }

    func test_parse_frontmatter_extractsInlineTokensFromInnerContent() {
        let markdown = """
        ---
        date: [[2024-11-22]]
        tags: [site](https://example.com)
        ---
        Body
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .frontmatter)
        XCTAssertEqual(document.blocks[0].inlineTokens.count, 2)
        XCTAssertEqual(document.blocks[0].inlineTokens[0].kind, .wikiLink(destination: "2024-11-22", alias: nil))
        XCTAssertEqual(document.blocks[0].inlineTokens[1].kind, .markdownLink(destination: "https://example.com"))
        XCTAssertEqual(substring(markdown, range: document.blocks[0].inlineTokens[0].range), "[[2024-11-22]]")
    }

    func test_parse_extractsInlineTokensWithUtf16Ranges() {
        let markdown = "Hi 😀 [[roadmap|Plan]] and [site](https://example.com) plus ![[spec]]"

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 1)
        guard let paragraph = document.blocks.first else {
            return XCTFail("Expected a paragraph block")
        }
        XCTAssertEqual(paragraph.kind, .paragraph)
        XCTAssertEqual(paragraph.inlineTokens.count, 3)

        let nsMarkdown = markdown as NSString

        XCTAssertEqual(paragraph.inlineTokens[0].kind, .wikiLink(destination: "roadmap", alias: "Plan"))
        XCTAssertEqual(paragraph.inlineTokens[0].range.location, nsMarkdown.range(of: "[[roadmap|Plan]]").location)
        XCTAssertEqual(substring(markdown, range: paragraph.inlineTokens[0].range), "[[roadmap|Plan]]")

        XCTAssertEqual(paragraph.inlineTokens[1].kind, .markdownLink(destination: "https://example.com"))
        XCTAssertEqual(paragraph.inlineTokens[1].range.location, nsMarkdown.range(of: "[site](https://example.com)").location)
        XCTAssertEqual(substring(markdown, range: paragraph.inlineTokens[1].range), "[site](https://example.com)")

        XCTAssertEqual(paragraph.inlineTokens[2].kind, .embed(destination: "spec"))
        XCTAssertEqual(paragraph.inlineTokens[2].range.location, nsMarkdown.range(of: "![[spec]]").location)
        XCTAssertEqual(substring(markdown, range: paragraph.inlineTokens[2].range), "![[spec]]")
    }

    func test_parse_extractsMarkdownImageInlineToken() {
        let markdown = "Look ![diagram](https://example.com/diagram.png) now"

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 1)
        let paragraph = document.blocks[0]
        XCTAssertEqual(paragraph.inlineTokens.count, 1)
        XCTAssertEqual(paragraph.inlineTokens[0].kind, .markdownImage(destination: "https://example.com/diagram.png", caption: "diagram"))
        XCTAssertEqual(substring(markdown, range: paragraph.inlineTokens[0].range), "![diagram](https://example.com/diagram.png)")
        XCTAssertEqual(substring(markdown, range: paragraph.inlineTokens[0].contentRange), "diagram")
    }

    func test_parse_recognizesValidPipeTableAsSingleBlock() {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | One | 1 |
        | Two | 2 |
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .table(columnCount: 2))
        XCTAssertEqual(substring(markdown, range: document.blocks[0].range), markdown)
    }

    func test_parse_malformedTableFallsBackToParagraphs() {
        let markdown = """
        | Name | Value |
        not a separator row
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
    }

    func test_parse_unclosedFenceBecomesCodeBlockToEndOfDocument() {
        let markdown = """
        ```swift
        let answer = 42
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .fencedCodeBlock(fence: "```", infoString: "swift"))
        XCTAssertEqual(substring(markdown, range: document.blocks[0].range), markdown)
    }

    func test_parse_contiguousBlockquoteLinesBecomeSingleBlock() {
        let markdown = """
        > First line
        > Second line

        After blank line
        """

        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .blockquote)
        XCTAssertTrue(substring(markdown, range: document.blocks[0].range).contains("> First line"))
        XCTAssertTrue(substring(markdown, range: document.blocks[0].range).contains("> Second line"))
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
    }

    func test_parse_blockquote_carriesInlineTokensInContent() {
        let markdown = "> See [[Other Note]] for details.\n"
        let document = parser.parse(markdown)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .blockquote)
        XCTAssertEqual(document.blocks[0].inlineTokens.count, 1)
        XCTAssertEqual(document.blocks[0].inlineTokens[0].kind, .wikiLink(destination: "Other Note", alias: nil))
    }

    private func substring(_ text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }
}
