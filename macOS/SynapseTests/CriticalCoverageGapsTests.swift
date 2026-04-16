import XCTest
@testable import Synapse

/// Regression tests for five high-impact behaviors that were easy to miss because they
/// live at the edges of parsers, shell boot strings, or persisted numeric limits.
final class CriticalCoverageGapsTests: XCTestCase {

    // MARK: 1 — Vault recency caps (sidebar + restore)

    func test_maxRecentTags_isTwenty() {
        XCTAssertEqual(AppConstants.maxRecentTags, 20)
    }

    func test_maxRecentFolders_isTwenty() {
        XCTAssertEqual(AppConstants.maxRecentFolders, 20)
    }

    // MARK: 2 — Task checkbox hits include `+` bullets and uppercase X

    func test_matches_plusBulletTask_isDetected() {
        let source = "+ [ ] Plus bullet task"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].isChecked, false)
        let ns = source as NSString
        XCTAssertEqual(ns.substring(with: hits[0].markerRange), "[ ]")
    }

    func test_matches_uppercaseXTask_isCheckedAndUnchecksToLowercaseX() {
        let source = "- [X] Done with caps"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].isChecked)
        XCTAssertEqual(hits[0].replacement, "[ ]")
    }

    func test_hit_uppercaseX_insideMarker_returnsHit() {
        let source = "- [X] Task"
        let hit = MarkdownTaskCheckboxInteraction.hit(in: source, at: 3)
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit?.isChecked == true)
    }

    // MARK: 3 — Terminal boot: spaced working directory + custom command

    func test_terminalBootCommand_customCommandWithSpacedWorkingDirectory() {
        let cmd = TerminalBootCommand.initialShellCommand(
            workingDirectory: "/Users/me/My Vault",
            onBootCommand: "git status"
        )
        XCTAssertEqual(cmd, "cd /Users/me/My\\ Vault && git status\n")
    }

    // MARK: 4 — Indented tasks: checkbox marker offset follows list indent

    func test_matches_indentedTask_markerRangeAccountsForIndent() {
        let source = "  - [ ] Indented task"
        let hits = MarkdownTaskCheckboxInteraction.matches(in: source)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].markerRange, NSRange(location: 4, length: 3))
        let ns = source as NSString
        XCTAssertEqual(ns.substring(with: hits[0].markerRange), "[ ]")
    }

    // MARK: 5 — Slash command token must be letters only (no `/done-1`)

    func test_slashCommandContext_rejectsSlashTokenWithHyphen() {
        let text = "See /done-1"
        let context = slashCommandContext(in: text, cursor: (text as NSString).length)
        XCTAssertNil(context)
    }
}
