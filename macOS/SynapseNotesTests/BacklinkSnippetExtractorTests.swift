import XCTest
@testable import Synapse

/// Tests for BacklinkSnippetExtractor — the pure logic behind backlink context
/// previews in the Related Links pane:
///   - Finding lines that mention a [[wikilink]] whose normalized target matches
///   - Alias ([[Note|alias]]) and heading ([[Note#Section]]) forms
///   - Capping, deduplication, trimming, and truncation of snippets
///   - The shared normalize() helper (pipe → hash → trim → lowercase)
final class BacklinkSnippetExtractorTests: XCTestCase {

    // MARK: - Basic matching

    func test_basicMatch_returnsLineTextAndLineNumber() {
        let content = "intro line\nSee [[Hub]] here\noutro"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.text, "See [[Hub]] here")
        XCTAssertEqual(snippets.first?.lineNumber, 2)
    }

    func test_match_isCaseInsensitive() {
        let content = "Mentions [[HUB]] loudly"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.lineNumber, 1)
    }

    // MARK: - Alias and heading forms

    func test_aliasForm_matches() {
        let content = "Read [[Hub|the big hub]] for details"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1)
    }

    func test_headingForm_matches() {
        let content = "Jump to [[Hub#Overview]] first"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1)
    }

    func test_aliasAndHeadingCombined_matches() {
        // Pipe split happens before hash split, matching AppState normalization
        let content = "Combined [[Hub#Section|alias text]] form"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1)
    }

    // MARK: - Non-matches

    func test_noWikilink_returnsEmpty() {
        let content = "This note never links anywhere"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertTrue(snippets.isEmpty)
    }

    func test_partialNameDoesNotMatch() {
        // [[Hubcap]] must not match target "hub" — exact normalized compare, not substring
        let content = "Talking about [[Hubcap]] only"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertTrue(snippets.isEmpty)
    }

    // MARK: - Capping and deduplication

    func test_multipleMentions_cappedAtMaxSnippets_inDocumentOrder() {
        let content = (1...5).map { "Line \($0) says [[Hub]]" }.joined(separator: "\n")
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 3, "Snippets should be capped at the default max of 3")
        XCTAssertEqual(snippets.map(\.lineNumber), [1, 2, 3],
            "Snippets should appear in document order")
    }

    func test_twoMentionsOnOneLine_yieldOneSnippet() {
        let content = "Both [[Hub]] and [[Hub|again]] on one line"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.count, 1,
            "Multiple mentions on the same line should be deduplicated to one snippet")
    }

    // MARK: - Trimming and truncation

    func test_whitespace_trimmed() {
        let content = "   indented [[Hub]] mention   "
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        XCTAssertEqual(snippets.first?.text, "indented [[Hub]] mention")
    }

    func test_longLine_truncatedToMaxLengthWithEllipsis() {
        let padding = String(repeating: "x", count: 300)
        let content = "[[Hub]] \(padding)"
        let snippets = BacklinkSnippetExtractor.snippets(ofNormalizedTarget: "hub", in: content)

        let text = snippets.first?.text ?? ""
        XCTAssertLessThanOrEqual(text.count, 160)
        XCTAssertTrue(text.hasSuffix("…"), "Truncated snippets should end with an ellipsis")
    }

    // MARK: - normalize()

    func test_normalize_pipeHashTrimLowercase() {
        XCTAssertEqual(BacklinkSnippetExtractor.normalize("Hub"), "hub")
        XCTAssertEqual(BacklinkSnippetExtractor.normalize("Hub|Alias"), "hub")
        XCTAssertEqual(BacklinkSnippetExtractor.normalize("Hub#Section"), "hub")
        XCTAssertEqual(BacklinkSnippetExtractor.normalize("Hub#Sec|Alias"), "hub")
        XCTAssertEqual(BacklinkSnippetExtractor.normalize("  Hub  "), "hub")
        XCTAssertEqual(BacklinkSnippetExtractor.normalize(""), "")
    }
}
