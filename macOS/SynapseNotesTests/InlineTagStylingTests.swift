import XCTest
import AppKit
@testable import Synapse

final class InlineTagStylingTests: XCTestCase {
    private var textView: LinkAwareTextView!

    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
    }

    override func tearDown() {
        textView = nil
        super.tearDown()
    }

    func test_applyMarkdownStyling_colorizesInlineTags() {
        let text = "Planning #work and #v2.1 today"

        textView.setPlainText(text)
        textView.applyMarkdownStyling()

        let nsText = text as NSString
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "#work").location + 1), SynapseTheme.editorLink)
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "#v2.1").location + 1), SynapseTheme.editorLink)
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "Planning").location), SynapseTheme.editorForeground)
    }

    func test_applyMarkdownStyling_ignoresNonTagFragments() {
        let text = "Skip /docs/#anchor and `#code` and #123 but keep #real"

        textView.setPlainText(text)
        textView.applyMarkdownStyling()

        let nsText = text as NSString
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "#anchor").location + 1), SynapseTheme.editorForeground)
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "#123").location + 1), SynapseTheme.editorForeground)
        XCTAssertEqual(foregroundColor(at: nsText.range(of: "#real").location + 1), SynapseTheme.editorLink)
    }

    private func foregroundColor(at index: Int) -> NSColor? {
        guard let storage = textView.textStorage, index < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }
}
