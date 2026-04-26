import XCTest
import AppKit
@testable import Synapse

final class MarkdownEditorInlineSemanticStylesTests: XCTestCase {
    func test_make_extractsMarkdownLinksWikiLinksAndEmbeds() {
        let markdown = "Read [docs](https://example.com) [[Roadmap|Plan]] ![[Spec#Intro|Shown]]"
        let styles = MarkdownEditorInlineSemanticStyles.make(from: markdown)
        let ns = markdown as NSString

        XCTAssertEqual(styles.entries.count, 3)

        XCTAssertEqual(styles.entries[0].range, ns.range(of: "[docs](https://example.com)"))
        XCTAssertEqual(styles.entries[0].contentRange, ns.range(of: "docs"))
        XCTAssertEqual(styles.entries[0].kind, .markdownLink(destination: "https://example.com"))

        XCTAssertEqual(styles.entries[1].range, ns.range(of: "[[Roadmap|Plan]]"))
        XCTAssertEqual(styles.entries[1].contentRange, ns.range(of: "Plan"))
        XCTAssertEqual(styles.entries[1].kind, .wikiLink(rawTarget: "Roadmap|Plan", destination: "Roadmap", alias: "Plan"))

        XCTAssertEqual(styles.entries[2].range, ns.range(of: "![[Spec#Intro|Shown]]"))
        XCTAssertEqual(styles.entries[2].contentRange, ns.range(of: "Spec#Intro|Shown"))
        XCTAssertEqual(styles.entries[2].kind, .embed(rawTarget: "Spec#Intro|Shown"))
    }

    func test_applyMarkdownStyling_usesSharedInlineSemanticsForEditorAttributes() {
        let textView = LinkAwareTextView()
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("Target.md")
        textView.allFiles = [targetURL]
        textView.string = "See [[Target|Shown]] and [site](https://example.com) plus ![[Spec]]"

        textView.applyMarkdownStyling()

        guard let storage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }

        let text = textView.string as NSString
        let wikiRange = text.range(of: "[[Target|Shown]]")
        let markdownLinkRange = text.range(of: "[site](https://example.com)")
        let markdownLabelRange = text.range(of: "site")
        let embedRange = text.range(of: "![[Spec]]")

        XCTAssertEqual(storage.attribute(.wikilinkTarget, at: wikiRange.location, effectiveRange: nil) as? String, "Target|Shown")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: wikiRange.location, effectiveRange: nil) as? NSColor, MarkdownTheme.linkColor)

        XCTAssertEqual(storage.attribute(.link, at: markdownLinkRange.location, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: markdownLabelRange.location, effectiveRange: nil) as? NSColor, MarkdownTheme.linkColor)

        XCTAssertEqual(storage.attribute(.link, at: embedRange.location, effectiveRange: nil) as? String, "Spec")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: embedRange.location, effectiveRange: nil) as? NSColor, MarkdownTheme.dimColor)
    }

    func test_applyMarkdownStyling_preservesWikilinkStylingInsideFrontmatter() {
        let textView = LinkAwareTextView()
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("2024-11-22.md")
        textView.allFiles = [targetURL]
        textView.string = "---\ndate: [[2024-11-22]]\n---\nBody"

        textView.applyMarkdownStyling()

        guard let storage = textView.textStorage else {
            return XCTFail("Expected text storage")
        }

        let text = textView.string as NSString
        let wikiRange = text.range(of: "[[2024-11-22]]")

        XCTAssertEqual(storage.attribute(.wikilinkTarget, at: wikiRange.location, effectiveRange: nil) as? String, "2024-11-22")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: wikiRange.location, effectiveRange: nil) as? NSColor, MarkdownTheme.linkColor)
        XCTAssertEqual((storage.attribute(.font, at: wikiRange.location, effectiveRange: nil) as? NSFont)?.pointSize, 11)
    }
}
