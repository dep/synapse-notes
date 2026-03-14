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
}
