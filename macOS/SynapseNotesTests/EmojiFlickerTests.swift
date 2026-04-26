import XCTest
import AppKit
@testable import Synapse

/// Tests for Issue: emoji flicker during typing.
///
/// The flicker happens because `applyMarkdownStyling` calls `restoreEmojiFonts`
/// immediately after the blanket `setAttributes` reset, but before the per-block
/// styling passes (headings, bold, italic, etc.). Those later passes use
/// `addAttributes([.font: headingFont, ...])` which overwrites the emoji font
/// that `restoreEmojiFonts` just set, leaving emojis with the wrong font until
/// Core Text substitutes — causing a visible flash.
///
/// The fix: move `restoreEmojiFonts` to after ALL font-setting styling passes.
final class EmojiFlickerTests: XCTestCase {

    // MARK: - Helpers

    private func makeTextView(string: String) -> LinkAwareTextView {
        let tv = LinkAwareTextView()
        tv.string = string
        return tv
    }

    private func emojiFont(pointSize: CGFloat) -> NSFont {
        NSFont(name: "Apple Color Emoji", size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize)
    }

    // MARK: - Emoji in plain paragraph keeps Apple Color Emoji font

    func test_emojiInPlainParagraph_hasEmojiFont_afterStyling() {
        let tv = makeTextView(string: "Hello 🎉 world")
        tv.applyMarkdownStyling()

        guard let storage = tv.textStorage else { return XCTFail("no storage") }
        let text = tv.string as NSString
        let emojiRange = text.range(of: "🎉")
        XCTAssertTrue(emojiRange.location != NSNotFound, "emoji must be in string")

        let font = storage.attribute(.font, at: emojiRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji",
                       "emoji in plain paragraph should have Apple Color Emoji font after styling")
    }

    // MARK: - Emoji inside a heading keeps Apple Color Emoji font

    /// This is the primary regression test for the flicker bug.
    /// Previously, restoreEmojiFonts ran before the heading styling pass.
    /// The heading pass then called addAttributes([.font: h1Font]) over the emoji,
    /// replacing the emoji font with h1Font — causing flicker.
    func test_emojiInHeading_hasEmojiFont_afterStyling() {
        let tv = makeTextView(string: "# Welcome 🎉\n\nSome body text.")
        tv.applyMarkdownStyling()

        guard let storage = tv.textStorage else { return XCTFail("no storage") }
        let text = tv.string as NSString
        let emojiRange = text.range(of: "🎉")
        XCTAssertTrue(emojiRange.location != NSNotFound, "emoji must be in string")

        let font = storage.attribute(.font, at: emojiRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji",
                       "emoji inside a heading should retain Apple Color Emoji font after heading styling pass")
    }

    // MARK: - Emoji inside bold text keeps Apple Color Emoji font

    func test_emojiInBoldText_hasEmojiFont_afterStyling() {
        let tv = makeTextView(string: "This is **bold 🔥 text**")
        tv.applyMarkdownStyling()

        guard let storage = tv.textStorage else { return XCTFail("no storage") }
        let text = tv.string as NSString
        let emojiRange = text.range(of: "🔥")
        XCTAssertTrue(emojiRange.location != NSNotFound, "emoji must be in string")

        let font = storage.attribute(.font, at: emojiRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji",
                       "emoji inside bold text should retain Apple Color Emoji font after bold styling pass")
    }

    // MARK: - Emoji inside italic text keeps Apple Color Emoji font

    func test_emojiInItalicText_hasEmojiFont_afterStyling() {
        let tv = makeTextView(string: "This is *italic 🌊 text*")
        tv.applyMarkdownStyling()

        guard let storage = tv.textStorage else { return XCTFail("no storage") }
        let text = tv.string as NSString
        let emojiRange = text.range(of: "🌊")
        XCTAssertTrue(emojiRange.location != NSNotFound, "emoji must be in string")

        let font = storage.attribute(.font, at: emojiRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "AppleColorEmoji",
                       "emoji inside italic text should retain Apple Color Emoji font after italic styling pass")
    }

    // MARK: - Multiple emoji across mixed content all keep Apple Color Emoji font

    func test_multipleEmoji_inMixedContent_allHaveEmojiFont() {
        let tv = makeTextView(string: "# Heading 🎯\n\nPlain 🎉 text with **bold 🔥**")
        tv.applyMarkdownStyling()

        guard let storage = tv.textStorage else { return XCTFail("no storage") }
        let text = tv.string as NSString

        for emoji in ["🎯", "🎉", "🔥"] {
            let range = text.range(of: emoji)
            XCTAssertTrue(range.location != NSNotFound, "\(emoji) must be in string")
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            XCTAssertEqual(font?.fontName, "AppleColorEmoji",
                           "\(emoji) should have Apple Color Emoji font after all styling passes")
        }
    }
}
