import XCTest
@testable import Synapse

/// Tests for GitService.shellQuote(_:) — the POSIX single-quote escaping that protects
/// every git argument passed through the login shell from injection and misinterpretation.
///
/// Correctness is critical: a regression here would silently break all git operations for
/// vaults whose paths contain apostrophes (e.g. "Alice's Notes/") and could allow
/// argument injection in edge-case inputs.
final class GitShellQuoteTests: XCTestCase {

    // MARK: - Basic quoting

    func test_shellQuote_plainString_wrapsInSingleQuotes() {
        XCTAssertEqual(GitService.shellQuote("hello"), "'hello'")
    }

    func test_shellQuote_emptyString_returnsEmptyQuotedPair() {
        XCTAssertEqual(GitService.shellQuote(""), "''")
    }

    func test_shellQuote_stringWithSpaces_preservesSpaces() {
        XCTAssertEqual(GitService.shellQuote("my vault"), "'my vault'")
    }

    func test_shellQuote_stringWithPath_preservesSlashes() {
        XCTAssertEqual(GitService.shellQuote("/Users/alice/notes"), "'/Users/alice/notes'")
    }

    // MARK: - Apostrophe escaping

    func test_shellQuote_singleApostrophe_escapesCorrectly() {
        // "it's" → 'it'\''s'
        XCTAssertEqual(GitService.shellQuote("it's"), "'it'\\''s'")
    }

    func test_shellQuote_multipleApostrophes_escapesAll() {
        // "Alice's Vault's" → 'Alice'\''s Vault'\''s'
        XCTAssertEqual(GitService.shellQuote("Alice's Vault's"), "'Alice'\\''s Vault'\\''s'")
    }

    func test_shellQuote_stringOfOnlyApostrophe_escapesCorrectly() {
        // "'" → ''\''"
        XCTAssertEqual(GitService.shellQuote("'"), "''\\'''")
    }

    func test_shellQuote_leadingApostrophe_escapesCorrectly() {
        // "'hello" → ''\''hello'
        XCTAssertEqual(GitService.shellQuote("'hello"), "''\\''hello'")
    }

    func test_shellQuote_trailingApostrophe_escapesCorrectly() {
        // "hello'" → 'hello'\'''
        XCTAssertEqual(GitService.shellQuote("hello'"), "'hello'\\'''")
    }

    // MARK: - Injection safety

    func test_shellQuote_subshellExpansion_contained() {
        // "$(rm -rf /)" should be quoted so the shell never evaluates it
        let result = GitService.shellQuote("$(rm -rf /)")
        XCTAssertEqual(result, "'$(rm -rf /)'",
                       "Subshell expansion characters should be contained inside single quotes")
    }

    func test_shellQuote_backtickExpansion_contained() {
        let result = GitService.shellQuote("`whoami`")
        XCTAssertEqual(result, "'`whoami`'",
                       "Backtick expansion should be contained inside single quotes")
    }

    func test_shellQuote_semicolonAndAmpersand_contained() {
        // Semicolons and ampersands are shell metacharacters
        let result = GitService.shellQuote("note; rm -rf /tmp")
        XCTAssertEqual(result, "'note; rm -rf /tmp'",
                       "Shell metacharacters should be contained in single quotes")
    }

    func test_shellQuote_dollarAndDoubleQuote_contained() {
        let result = GitService.shellQuote("$HOME/\"docs\"")
        XCTAssertEqual(result, "'$HOME/\"docs\"'",
                       "Dollar signs and double quotes should be contained in single quotes")
    }

    // MARK: - Other special characters (preserved as-is inside quotes)

    func test_shellQuote_backslash_preserved() {
        XCTAssertEqual(GitService.shellQuote("back\\slash"), "'back\\slash'")
    }

    func test_shellQuote_newline_preserved() {
        XCTAssertEqual(GitService.shellQuote("line1\nline2"), "'line1\nline2'")
    }

    func test_shellQuote_asteriskAndBrackets_preserved() {
        // Glob characters should be inert inside single quotes
        XCTAssertEqual(GitService.shellQuote("*.md"), "'*.md'")
        XCTAssertEqual(GitService.shellQuote("[0-9]"), "'[0-9]'")
    }

    // MARK: - Structural invariants

    func test_shellQuote_result_alwaysStartsAndEndsWithSingleQuote() {
        let inputs = ["", "hello", "it's fine", "$(cmd)", "a'b'c"]
        for input in inputs {
            let result = GitService.shellQuote(input)
            XCTAssertTrue(result.hasPrefix("'"),
                          "Result should start with single quote for input: \(input)")
            XCTAssertTrue(result.hasSuffix("'"),
                          "Result should end with single quote for input: \(input)")
        }
    }

    func test_shellQuote_apostropheEscapePattern_isCorrectPosixSequence() {
        // POSIX single-quote escape: end-quote + backslash + apostrophe + start-quote
        let result = GitService.shellQuote("a'b")
        XCTAssertTrue(result.contains("'\\''"),
                      "Apostrophe escape must use POSIX '\\'\\'' sequence, got: \(result)")
    }
}
