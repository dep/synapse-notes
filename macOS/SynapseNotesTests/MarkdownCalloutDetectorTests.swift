import XCTest
@testable import Synapse

/// Tests for MarkdownCalloutDetector — the parser that recognises Obsidian-style
/// callout blocks (`> [!NOTE]`, `> [!WARNING]+`, etc.) inside blockquotes.
///
/// Callouts are a first-class feature: they drive special styling, icon rendering,
/// and the collapsible (+/-) indicator. Regressions here break a prominently
/// visible piece of markdown rendering.
final class MarkdownCalloutDetectorTests: XCTestCase {

    private var docParser: MarkdownDocumentParser!

    override func setUp() {
        super.setUp()
        docParser = MarkdownDocumentParser()
    }

    override func tearDown() {
        docParser = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func firstBlockquoteBlock(in source: String) -> MarkdownBlock? {
        docParser.parse(source).blocks.first { block in
            if case .blockquote = block.kind { return true }
            return false
        }
    }

    private func detect(_ source: String) -> MarkdownCallout? {
        guard let block = firstBlockquoteBlock(in: source) else { return nil }
        return MarkdownCalloutDetector.detect(in: block, source: source)
    }

    // MARK: - Basic detection

    func test_detect_simpleNoteCallout_returnsNonNil() {
        let source = "> [!NOTE] This is a note\n> Body text"

        let callout = detect(source)

        XCTAssertNotNil(callout, "A well-formed [!NOTE] callout must be detected")
    }

    func test_detect_kind_isLowercased() {
        let source = "> [!WARNING] Watch out"

        let callout = detect(source)

        XCTAssertEqual(callout?.kind, "warning", "Callout kind must be lowercased — got: \(callout?.kind ?? "nil")")
    }

    func test_detect_tipCallout_kindIsTip() {
        let source = "> [!TIP] A helpful tip"

        let callout = detect(source)

        XCTAssertEqual(callout?.kind, "tip")
    }

    func test_detect_infoCallout_kindIsInfo() {
        let source = "> [!INFO] For your information"

        let callout = detect(source)

        XCTAssertEqual(callout?.kind, "info")
    }

    // MARK: - Collapsible modifiers (+ and -)

    func test_detect_expandableModifier_markerRangeIncludesPlus() {
        let source = "> [!NOTE]+ Expandable\n> Body"

        let callout = detect(source)

        XCTAssertNotNil(callout, "Callout with '+' modifier should be detected")
        let nsSource = source as NSString
        let markerText = nsSource.substring(with: callout!.markerRange)
        XCTAssertTrue(markerText.contains("+"), "Marker range must include the '+' modifier — got: \(markerText)")
    }

    func test_detect_collapsibleModifier_markerRangeIncludesMinus() {
        let source = "> [!NOTE]- Collapsed\n> Body"

        let callout = detect(source)

        XCTAssertNotNil(callout, "Callout with '-' modifier should be detected")
        let nsSource = source as NSString
        let markerText = nsSource.substring(with: callout!.markerRange)
        XCTAssertTrue(markerText.contains("-"), "Marker range must include the '-' modifier — got: \(markerText)")
    }

    func test_detect_withPlus_kindDoesNotContainPlus() {
        let source = "> [!NOTE]+ Title"

        let callout = detect(source)

        XCTAssertNotNil(callout)
        XCTAssertEqual(callout?.kind, "note", "Kind must not include '+' — got: \(callout?.kind ?? "nil")")
    }

    func test_detect_withMinus_kindDoesNotContainMinus() {
        let source = "> [!WARNING]- Title"

        let callout = detect(source)

        XCTAssertNotNil(callout)
        XCTAssertEqual(callout?.kind, "warning", "Kind must not include '-' — got: \(callout?.kind ?? "nil")")
    }

    // MARK: - Title range

    func test_detect_withTitle_titleRangeIsNonNil() {
        let source = "> [!NOTE] My Title"

        let callout = detect(source)

        XCTAssertNotNil(callout?.titleRange, "Callout with a title must have a non-nil titleRange")
    }

    func test_detect_withTitle_titleRangeCoversTitle() {
        let source = "> [!NOTE] My Title"
        let nsSource = source as NSString

        let callout = detect(source)

        XCTAssertNotNil(callout?.titleRange)
        let extractedTitle = nsSource.substring(with: callout!.titleRange!)
        XCTAssertEqual(extractedTitle, "My Title", "titleRange must span exactly the title text — got: \(extractedTitle)")
    }

    func test_detect_withoutTitle_titleRangeIsNil() {
        let source = "> [!NOTE]\n> Body only, no title on header line"

        let callout = detect(source)

        XCTAssertNil(callout?.titleRange, "A callout without a title must have a nil titleRange")
    }

    // MARK: - Not a callout

    func test_detect_plainBlockquote_returnsNil() {
        let source = "> Just a regular blockquote"

        let callout = detect(source)

        XCTAssertNil(callout, "A plain blockquote without [!type] must not be detected as a callout")
    }

    func test_detect_missingExclamation_returnsNil() {
        let source = "> [NOTE] Missing exclamation"

        let callout = detect(source)

        XCTAssertNil(callout, "A blockquote with [NOTE] (no '!') must not be detected as a callout")
    }

    func test_detect_emptyKind_returnsNil() {
        // "[!]" has an empty kind after stripping brackets and "!".
        let source = "> [!] Empty kind"

        let callout = detect(source)

        XCTAssertNil(callout, "A callout with an empty kind '[!]' must not be detected")
    }

    func test_detect_nonBlockquote_returnsNil() {
        // A heading is not a blockquote block, so detection must return nil.
        let source = "# [!NOTE] Not a blockquote"

        let callout = detect(source)

        XCTAssertNil(callout, "Non-blockquote blocks must not produce a callout")
    }

    // MARK: - Range sanity checks

    func test_detect_blockRange_coversEntireBlockquote() {
        let source = "> [!NOTE] Title\n> Body line"
        let nsSource = source as NSString

        let callout = detect(source)

        XCTAssertNotNil(callout)
        let blockText = nsSource.substring(with: callout!.blockRange)
        XCTAssertTrue(blockText.contains("[!NOTE]"), "blockRange must cover the entire blockquote content")
    }

    func test_detect_markerRange_coversMarker() {
        let source = "> [!DANGER] Watch out"
        let nsSource = source as NSString

        let callout = detect(source)

        XCTAssertNotNil(callout)
        let markerText = nsSource.substring(with: callout!.markerRange)
        XCTAssertTrue(markerText.contains("[!"), "markerRange must cover the [!TYPE] marker — got: \(markerText)")
    }

    func test_detect_headerRange_isFirstLine() {
        let source = "> [!INFO] Info title\n> This is the body"
        let nsSource = source as NSString

        let callout = detect(source)

        XCTAssertNotNil(callout)
        let headerText = nsSource.substring(with: callout!.headerRange).trimmingCharacters(in: .newlines)
        XCTAssertTrue(headerText.contains("[!INFO]"), "headerRange should point to the first (header) line — got: \(headerText)")
        XCTAssertFalse(headerText.contains("body"), "headerRange must not extend into the body line")
    }

    // MARK: - Multiline callout

    func test_detect_multilineCallout_stillDetected() {
        let source = "> [!NOTE] Title\n> First body line\n> Second body line"

        let callout = detect(source)

        XCTAssertNotNil(callout, "A multi-line callout should still be detected from the header")
        XCTAssertEqual(callout?.kind, "note")
    }

    // MARK: - Case-insensitive kind normalisation

    func test_detect_mixedCaseKind_isFullyLowercased() {
        let source = "> [!InFo] Mixed case kind"

        let callout = detect(source)

        XCTAssertNotNil(callout)
        XCTAssertEqual(callout?.kind, "info", "Kind must always be lowercased regardless of input case")
    }
}
