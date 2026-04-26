import XCTest
import AppKit
@testable import Synapse

/// Tests for FontEnumerator — system font listing and filtering used by the font picker.
/// Wrong sorting or filtering breaks monospace/body font selection in settings.
final class FontEnumeratorTests: XCTestCase {

    // MARK: - allSystemFonts

    func test_allSystemFonts_isNonEmpty() {
        XCTAssertFalse(FontEnumerator.allSystemFonts().isEmpty,
                       "allSystemFonts() must return at least one font on any macOS install")
    }

    func test_allSystemFonts_isSortedCaseInsensitive() {
        let fonts = FontEnumerator.allSystemFonts()
        let sorted = fonts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(fonts, sorted, "allSystemFonts() must be sorted case-insensitively A → Z")
    }

    func test_allSystemFonts_containsHelvetica() {
        // Helvetica has shipped with macOS since the beginning; its absence would
        // indicate something is fundamentally broken with font enumeration.
        let fonts = FontEnumerator.allSystemFonts()
        XCTAssertTrue(fonts.contains("Helvetica"), "Helvetica must be present in allSystemFonts()")
    }

    func test_allSystemFonts_noEmptyStrings() {
        let fonts = FontEnumerator.allSystemFonts()
        XCTAssertFalse(fonts.contains(""), "allSystemFonts() must not include empty string entries")
    }

    // MARK: - monospaceFonts

    func test_monospaceFonts_isSubsetOfAllSystemFonts() {
        let all = Set(FontEnumerator.allSystemFonts())
        let mono = FontEnumerator.monospaceFonts()
        for font in mono {
            XCTAssertTrue(all.contains(font),
                          "monospaceFonts() returned '\(font)' which is not in allSystemFonts()")
        }
    }

    func test_monospaceFonts_isNonEmpty() {
        // Every Mac ships with at least one monospace font (e.g. Courier, Menlo, Monaco).
        XCTAssertFalse(FontEnumerator.monospaceFonts().isEmpty,
                       "monospaceFonts() must return at least one font on any macOS install")
    }

    func test_monospaceFonts_allHaveMonospaceTraitInNSFont() {
        for familyName in FontEnumerator.monospaceFonts() {
            if let font = NSFont(name: familyName, size: 12) ?? NSFont(name: "\(familyName)-Regular", size: 12) {
                let traits = font.fontDescriptor.symbolicTraits
                XCTAssertTrue(traits.contains(.monoSpace),
                              "'\(familyName)' was returned by monospaceFonts() but lacks the .monoSpace symbolic trait")
            }
        }
    }

    func test_monospaceFonts_containsMenloOrCourierOrMonaco() {
        let mono = FontEnumerator.monospaceFonts()
        let wellKnownMonoFonts = ["Menlo", "Courier", "Monaco", "Courier New"]
        let found = wellKnownMonoFonts.filter { mono.contains($0) }
        XCTAssertFalse(found.isEmpty,
                       "Expected at least one of \(wellKnownMonoFonts) in monospaceFonts() — got: \(mono.prefix(10))")
    }

    // MARK: - bodyFonts

    func test_bodyFonts_isSubsetOfAllSystemFonts() {
        let all = Set(FontEnumerator.allSystemFonts())
        let body = FontEnumerator.bodyFonts()
        for font in body {
            XCTAssertTrue(all.contains(font),
                          "bodyFonts() returned '\(font)' which is not in allSystemFonts()")
        }
    }

    func test_bodyFonts_isNonEmpty() {
        XCTAssertFalse(FontEnumerator.bodyFonts().isEmpty,
                       "bodyFonts() must return at least one font on any macOS install")
    }

    func test_bodyFonts_excludesWebdings() {
        let body = FontEnumerator.bodyFonts()
        XCTAssertFalse(body.contains("Webdings"),
                       "Webdings is a symbol/dingbat font and must be excluded from bodyFonts()")
    }

    func test_bodyFonts_excludesWingdings() {
        let body = FontEnumerator.bodyFonts()
        let wingdings = body.filter { $0.hasPrefix("Wingdings") }
        XCTAssertTrue(wingdings.isEmpty,
                      "Wingdings family must be excluded from bodyFonts() — found: \(wingdings)")
    }

    func test_bodyFonts_excludesAppleSymbols() {
        let body = FontEnumerator.bodyFonts()
        XCTAssertFalse(body.contains("Apple Symbols"),
                       "Apple Symbols must be excluded from bodyFonts()")
    }

    func test_bodyFonts_containsHelvetica() {
        XCTAssertTrue(FontEnumerator.bodyFonts().contains("Helvetica"),
                      "Helvetica is a standard body font and must not be excluded")
    }

    func test_bodyFonts_isSmallerThanOrEqualToAllSystemFonts() {
        XCTAssertLessThanOrEqual(FontEnumerator.bodyFonts().count, FontEnumerator.allSystemFonts().count,
                                 "bodyFonts() should never contain more fonts than allSystemFonts()")
    }

    // MARK: - displayName

    func test_displayName_emptyFamilyName_nonMonospace_returnsSystem() {
        XCTAssertEqual(FontEnumerator.displayName(for: "", isMonospace: false), "System",
                       "Empty font family with isMonospace=false should return 'System'")
    }

    func test_displayName_emptyFamilyName_monospace_returnsSystemMonospace() {
        XCTAssertEqual(FontEnumerator.displayName(for: "", isMonospace: true), "System Monospace",
                       "Empty font family with isMonospace=true should return 'System Monospace'")
    }

    func test_displayName_nonEmptyFamilyName_returnsUnchanged() {
        XCTAssertEqual(FontEnumerator.displayName(for: "Helvetica"), "Helvetica",
                       "A non-empty font family name must be returned unchanged")
    }

    func test_displayName_nonEmptyFamilyName_monospaceFlag_returnsUnchanged() {
        XCTAssertEqual(FontEnumerator.displayName(for: "Menlo", isMonospace: true), "Menlo",
                       "A non-empty font family name must be returned unchanged regardless of isMonospace")
    }

    // MARK: - Consistency

    func test_callingAllSystemFontsTwice_returnsSameResult() {
        let first = FontEnumerator.allSystemFonts()
        let second = FontEnumerator.allSystemFonts()
        XCTAssertEqual(first, second, "allSystemFonts() must be deterministic across multiple calls")
    }

    func test_callingMonospaceFontsTwice_returnsSameResult() {
        let first = FontEnumerator.monospaceFonts()
        let second = FontEnumerator.monospaceFonts()
        XCTAssertEqual(first, second, "monospaceFonts() must be deterministic across multiple calls")
    }
}
