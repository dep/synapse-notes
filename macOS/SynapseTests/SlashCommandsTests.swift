import XCTest
import AppKit
@testable import Synapse

final class SlashCommandsTests: XCTestCase {
    func test_slashCommandContext_detectsSlashTokenAtStartOfLine() {
        let text = "Title\n/time"

        let context = slashCommandContext(in: text, cursor: (text as NSString).length)

        XCTAssertEqual(context, SlashCommandContext(range: NSRange(location: 6, length: 5), query: "time"))
    }

    func test_slashCommandContext_detectsSlashAfterSpace() {
        let text = "# /date"

        let context = slashCommandContext(in: text, cursor: (text as NSString).length)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.query, "date")
        XCTAssertEqual((text as NSString).substring(with: context!.range), "/date")
    }

    func test_slashCommandContext_ignoresSlashWithNoLeadingSpace() {
        // "foo/time" — slash directly after non-whitespace, not a command
        let text = "foo/time"

        let context = slashCommandContext(in: text, cursor: (text as NSString).length)

        XCTAssertNil(context)
    }

    func test_resolveSlashCommandOutput_formatsDateTimeAndFilenameCommands() {
        let now = Date(timeIntervalSince1970: 1_773_498_840)
        let context = SlashCommandResolverContext(
            now: now,
            currentFileURL: URL(fileURLWithPath: "/tmp/my-note.md"),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(resolveSlashCommandOutput(.time, context: context), "2:34 pm")
        XCTAssertEqual(resolveSlashCommandOutput(.date, context: context), "2026-03-14")
        XCTAssertEqual(resolveSlashCommandOutput(.todo, context: context), "- [ ] ")
        XCTAssertEqual(resolveSlashCommandOutput(.note, context: context), "> **Note:** ")
    }

    func test_expandSlashCommandIfNeeded_expandsExactCommandInPlace() {
        let textView = LinkAwareTextView()
        textView.currentFileURL = URL(fileURLWithPath: "/tmp/my-note.md")
        textView.slashCommandNowProvider = { Date(timeIntervalSince1970: 1_773_498_840) }
        textView.slashCommandTimeZone = TimeZone(secondsFromGMT: 0)!
        textView.string = "/time"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "2:34 pm")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))
    }

    func test_expandSlashCommandIfNeeded_doesNotExpandPartialCommand() {
        let textView = LinkAwareTextView()
        textView.string = "/ti"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "/ti")  // unchanged
    }

    func test_expandSlashCommandIfNeeded_expandsSlashAfterSpace() {
        let textView = LinkAwareTextView()
        textView.slashCommandNowProvider = { Date(timeIntervalSince1970: 1_773_498_840) }
        textView.slashCommandTimeZone = TimeZone(secondsFromGMT: 0)!
        textView.string = "some text /time"
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "some text 2:34 pm")
    }

    func test_expandSlashCommandIfNeeded_doesNotExpandSlashWithNoLeadingSpace() {
        let textView = LinkAwareTextView()
        textView.string = "foo/time"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "foo/time")  // unchanged
    }

    func test_expandSlashCommandIfNeeded_expandsTodoCommand() {
        let textView = LinkAwareTextView()
        textView.slashCommandNowProvider = { Date(timeIntervalSince1970: 1_773_498_840) }
        textView.string = "/todo"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "- [ ] ")
    }

    func test_slashCommandContext_worksAfterEmojiOnPreviousLine() {
        // Emoji are multi-byte in UTF-16; lineStart must be in NSString (UTF-16) units
        let text = "🌨️ weather\n/time"
        let nsText = text as NSString

        let context = slashCommandContext(in: text, cursor: nsText.length)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.query, "time")
        XCTAssertEqual(nsText.substring(with: context!.range), "/time")
    }

    func test_expandSlashCommandIfNeeded_expandsOnSecondLine() {
        let textView = LinkAwareTextView()
        textView.slashCommandNowProvider = { Date(timeIntervalSince1970: 1_773_498_840) }
        textView.slashCommandTimeZone = TimeZone(secondsFromGMT: 0)!
        textView.string = "First line\n/date"
        let cursor = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: cursor, length: 0))

        textView.expandSlashCommandIfNeeded()

        XCTAssertEqual(textView.string, "First line\n2026-03-14")
    }

    // MARK: - slashCommandContext input guard edge cases

    func test_slashCommandContext_cursorAtZero_returnsNil() {
        XCTAssertNil(slashCommandContext(in: "/time", cursor: 0),
                     "cursor == 0 should satisfy the clampedCursor > 0 guard and return nil")
    }

    func test_slashCommandContext_soloSlash_returnsNil() {
        // "/" alone does not match ^/[A-Za-z]+$
        XCTAssertNil(slashCommandContext(in: "/", cursor: 1),
                     "A bare '/' with no letters after it should not be recognised as a command")
    }

    func test_slashCommandContext_tokenWithTrailingDigit_returnsNil() {
        // "/time2" does not match ^/[A-Za-z]+$ because of the trailing digit.
        XCTAssertNil(slashCommandContext(in: "/time2", cursor: 6),
                     "A token ending in a digit (/time2) should not match the command regex")
    }

    func test_slashCommandContext_tokenWithEmbeddedDigit_returnsNil() {
        XCTAssertNil(slashCommandContext(in: "/d4te", cursor: 5),
                     "A token containing a digit (/d4te) should not match the command regex")
    }

    func test_slashCommandContext_cursorBeyondEnd_clampsAndDetectsCommand() {
        // A cursor value larger than the string length should be clamped to the length.
        let text = "/date"
        let result = slashCommandContext(in: text, cursor: 999)
        XCTAssertNotNil(result, "An out-of-bounds cursor should be clamped and still detect the command")
        XCTAssertEqual(result?.query, "date")
    }

    func test_slashCommandContext_negativeCursor_returnsNil() {
        // A negative cursor is clamped to 0, which then fails the clampedCursor > 0 guard.
        XCTAssertNil(slashCommandContext(in: "/time", cursor: -5),
                     "A negative cursor should be clamped to 0 and return nil")
    }

    func test_slashCommand_allCasesHasExactlyFourEntries() {
        // Guards against accidentally adding a case without a corresponding resolver branch.
        XCTAssertEqual(SlashCommand.allCases.count, 4)
        XCTAssertTrue(SlashCommand.allCases.contains(.time))
        XCTAssertTrue(SlashCommand.allCases.contains(.date))
        XCTAssertTrue(SlashCommand.allCases.contains(.todo))
        XCTAssertTrue(SlashCommand.allCases.contains(.note))
    }

    func test_slashCommandContext_urlPath_doesNotMatch() {
        // The "/time" in a URL is preceded by a non-whitespace char ('m' from ".com"),
        // so the preceding-char guard should reject it.
        let text = "https://example.com/time"
        XCTAssertNil(slashCommandContext(in: text, cursor: (text as NSString).length),
                     "A slash that appears inside a URL should not be treated as a command trigger")
    }

    func test_slashCommandContext_slashWithLeadingAlphanumeric_returnsNil() {
        // "path/date" — the slash follows a non-whitespace character.
        let text = "path/date"
        XCTAssertNil(slashCommandContext(in: text, cursor: (text as NSString).length),
                     "A slash immediately after a non-whitespace character should not trigger a command")
    }
}
