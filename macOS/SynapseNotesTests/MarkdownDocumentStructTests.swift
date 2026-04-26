import XCTest
@testable import Synapse

/// Tests for MarkdownDocument value semantics and parse edge cases that drive editor structure.
final class MarkdownDocumentStructTests: XCTestCase {

    private let parser = MarkdownDocumentParser()

    func test_parse_whitespaceOnlySource_yieldsNoBlocks() {
        let source = "   \n\n  \t  "
        let doc = parser.parse(source)
        XCTAssertTrue(doc.blocks.isEmpty)
        XCTAssertEqual(doc.source, source)
    }

    func test_markdownDocument_equatable_sameSourceAndBlocks() {
        let source = "# H\n\nPara"
        let a = parser.parse(source)
        let b = parser.parse(source)
        XCTAssertEqual(a, b)
    }

    func test_markdownDocument_equatable_differentBlockCount_notEqual() {
        let a = parser.parse("# One")
        let b = parser.parse("# One\n\n# Two")
        XCTAssertNotEqual(a, b)
    }

    func test_parse_taskListItem_blockKindCarriesIndent() {
        let source = "  - [ ] Indented task"
        let doc = parser.parse(source)
        guard let task = doc.blocks.first else {
            return XCTFail("Expected a block")
        }
        guard case let .taskListItem(indent, isChecked) = task.kind else {
            return XCTFail("Expected task list item")
        }
        XCTAssertEqual(indent, 2)
        XCTAssertFalse(isChecked)
    }
}
