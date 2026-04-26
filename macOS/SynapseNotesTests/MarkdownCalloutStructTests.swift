import XCTest
@testable import Synapse

/// Tests for MarkdownCallout — value semantics for callout metadata used by preview and styling.
final class MarkdownCalloutStructTests: XCTestCase {

    func test_markdownCallout_equatable_sameRangesAndKind() {
        let a = MarkdownCallout(
            blockRange: NSRange(location: 0, length: 10),
            headerRange: NSRange(location: 0, length: 5),
            markerRange: NSRange(location: 2, length: 8),
            titleRange: NSRange(location: 11, length: 4),
            kind: "note"
        )
        let b = MarkdownCallout(
            blockRange: NSRange(location: 0, length: 10),
            headerRange: NSRange(location: 0, length: 5),
            markerRange: NSRange(location: 2, length: 8),
            titleRange: NSRange(location: 11, length: 4),
            kind: "note"
        )
        XCTAssertEqual(a, b)
    }

    func test_markdownCallout_equatable_differentKind_notEqual() {
        let base = NSRange(location: 0, length: 10)
        let a = MarkdownCallout(blockRange: base, headerRange: base, markerRange: base, titleRange: nil, kind: "note")
        let b = MarkdownCallout(blockRange: base, headerRange: base, markerRange: base, titleRange: nil, kind: "warning")
        XCTAssertNotEqual(a, b)
    }

    func test_markdownCallout_equatable_nilVsNonNilTitle_notEqual() {
        let base = NSRange(location: 0, length: 10)
        let title = NSRange(location: 5, length: 3)
        let withTitle = MarkdownCallout(blockRange: base, headerRange: base, markerRange: base, titleRange: title, kind: "tip")
        let withoutTitle = MarkdownCallout(blockRange: base, headerRange: base, markerRange: base, titleRange: nil, kind: "tip")
        XCTAssertNotEqual(withTitle, withoutTitle)
    }
}
