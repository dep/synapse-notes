import XCTest
@testable import Synapse

/// Covers five high-impact UI-adjacent code paths that previously lived only inside SwiftUI views:
/// editor tab routing, tag filtering, terminal boot command, related-links title, and date-page headers.
final class CriticalSidebarAndEditorRoutingTests: XCTestCase {

    // MARK: - Editor tab routing (SplitPaneEditorView)

    func test_editorTabRouter_nilTab_returnsEditor() {
        XCTAssertEqual(EditorTabRouter.contentKind(for: nil), .editor)
    }

    func test_editorTabRouter_graphTab_returnsGlobalGraph() {
        XCTAssertEqual(EditorTabRouter.contentKind(for: .graph), .globalGraph)
    }

    func test_editorTabRouter_tagTab_returnsTagPage() {
        XCTAssertEqual(EditorTabRouter.contentKind(for: .tag("swift")), .tagPage(tag: "swift"))
    }

    func test_editorTabRouter_dateTab_returnsDatePage() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(EditorTabRouter.contentKind(for: .date(d)), .datePage(date: d))
    }

    func test_editorTabRouter_fileTab_returnsEditor() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        XCTAssertEqual(EditorTabRouter.contentKind(for: .file(url)), .editor)
    }

    // MARK: - Tags pane filtering (TagsPaneView)

    func test_tagsPaneFiltering_emptyQuery_sortsKeys() {
        let cache = ["zebra": 1, "alpha": 2]
        let result = TagsPaneFiltering.filteredTags(cache: cache, query: "")
        XCTAssertEqual(result.map(\.key), ["alpha", "zebra"])
        XCTAssertEqual(result.first?.value, 2)
    }

    func test_tagsPaneFiltering_caseInsensitiveSubstring() {
        let cache = ["SwiftUI": 3, "python": 1]
        let result = TagsPaneFiltering.filteredTags(cache: cache, query: "swift")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "SwiftUI")
    }

    func test_tagsPaneFiltering_noMatches_returnsEmpty() {
        let cache = ["a": 1]
        XCTAssertTrue(TagsPaneFiltering.filteredTags(cache: cache, query: "zzz").isEmpty)
    }

    // MARK: - Terminal boot command (LocalTerminalView)

    func test_terminalBootCommand_onlyCd_escapesSpacesAndNewline() {
        let cmd = TerminalBootCommand.initialShellCommand(
            workingDirectory: "/Users/me/My Vault",
            onBootCommand: nil
        )
        XCTAssertEqual(cmd, "cd /Users/me/My\\ Vault\n")
    }

    func test_terminalBootCommand_customCommand_appendsAfterCd() {
        let cmd = TerminalBootCommand.initialShellCommand(
            workingDirectory: "/repo",
            onBootCommand: "git status"
        )
        XCTAssertEqual(cmd, "cd /repo && git status\n")
    }

    func test_terminalBootCommand_emptyStringBoot_usesCdOnly() {
        let cmd = TerminalBootCommand.initialShellCommand(
            workingDirectory: "/tmp",
            onBootCommand: ""
        )
        XCTAssertEqual(cmd, "cd /tmp\n")
    }

    // MARK: - Related links title (RelatedLinksPaneView)

    func test_relatedLinksTitle_withFile_usesStem() {
        let url = URL(fileURLWithPath: "/vault/projects/Plan.md")
        XCTAssertEqual(RelatedLinksTitleText.title(selectedFile: url), "Plan")
    }

    func test_relatedLinksTitle_nilFile_fallsBack() {
        XCTAssertEqual(RelatedLinksTitleText.title(selectedFile: nil), "Related Notes")
    }

    // MARK: - Date page formatting (DatePageView)

    func test_datePageFormatting_isoTitle_matchesTabDisplayFormat() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 15)))
        XCTAssertEqual(DatePageFormatting.isoTitle(for: date), "2024-03-15")
    }

    func test_datePageFormatting_mediumSubtitle_nonEmpty() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(DatePageFormatting.mediumSubtitle(for: date).isEmpty)
    }
}
