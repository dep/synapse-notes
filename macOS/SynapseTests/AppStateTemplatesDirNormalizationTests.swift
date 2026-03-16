import XCTest
@testable import Synapse

/// Tests for AppState.templatesDirectoryURL() and the private
/// normalizedTemplatesDirectoryPath() helper it wraps.
///
/// These cover: whitespace trimming, leading/trailing slash stripping,
/// empty-after-trim fallback to the default directory, and the
/// isTemplatesDirectory() predicate that depends on the same normalization.
final class AppStateTemplatesDirNormalizationTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - templatesDirectoryURL() with no vault

    func test_templatesDirectoryURL_withNoVault_returnsNil() {
        let state = AppState()
        XCTAssertNil(state.templatesDirectoryURL(), "Without a vault, templatesDirectoryURL should be nil")
    }

    // MARK: - Whitespace trimming

    func test_leadingTrailingWhitespace_isTrimmed() {
        sut.settings.templatesDirectory = "  my-templates  "
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, "my-templates",
                       "Leading/trailing whitespace should be stripped from templates directory")
    }

    func test_tabsAndNewlines_areTrimmed() {
        sut.settings.templatesDirectory = "\t templates \n"
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, "templates")
    }

    // MARK: - Slash stripping

    func test_leadingSlash_isStripped() {
        sut.settings.templatesDirectory = "/templates"
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, "templates",
                       "Leading slash should be stripped from templates directory setting")
    }

    func test_trailingSlash_isStripped() {
        sut.settings.templatesDirectory = "templates/"
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, "templates",
                       "Trailing slash should be stripped from templates directory setting")
    }

    func test_leadingAndTrailingSlashes_areBothStripped() {
        sut.settings.templatesDirectory = "/my-templates/"
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, "my-templates",
                       "Both leading and trailing slashes should be stripped")
    }

    // MARK: - Empty / whitespace-only fallback

    func test_emptyString_usesDefaultTemplatesDirectory() {
        sut.settings.templatesDirectory = ""
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, AppConstants.defaultTemplatesDirectory,
                       "Empty templates directory should fall back to the default")
    }

    func test_whitespaceOnly_usesDefaultTemplatesDirectory() {
        sut.settings.templatesDirectory = "   "
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, AppConstants.defaultTemplatesDirectory,
                       "Whitespace-only templates directory should fall back to the default")
    }

    func test_slashOnly_usesDefaultTemplatesDirectory() {
        sut.settings.templatesDirectory = "/"
        let url = sut.templatesDirectoryURL()
        XCTAssertEqual(url?.lastPathComponent, AppConstants.defaultTemplatesDirectory,
                       "Slash-only setting should fall back to the default after stripping")
    }

    // MARK: - isTemplatesDirectory predicate

    func test_isTemplatesDirectory_recognizesNormalizedPath() {
        sut.settings.templatesDirectory = "/templates/"
        let templatesURL = sut.templatesDirectoryURL()!
        XCTAssertTrue(sut.isTemplatesDirectory(templatesURL),
                      "isTemplatesDirectory should recognize the normalized templates URL")
    }

    func test_isTemplatesDirectory_withLeadingWhitespace_stillRecognizes() {
        sut.settings.templatesDirectory = "  snippets  "
        let templatesURL = sut.templatesDirectoryURL()!
        XCTAssertTrue(sut.isTemplatesDirectory(templatesURL),
                      "isTemplatesDirectory should still recognize URL after whitespace normalization")
    }

    func test_isTemplatesDirectory_returnsFalseForUnrelatedURL() {
        sut.settings.templatesDirectory = "templates"
        let notesURL = tempDir.appendingPathComponent("notes", isDirectory: true)
        XCTAssertFalse(sut.isTemplatesDirectory(notesURL),
                       "isTemplatesDirectory should return false for a non-templates directory")
    }

    func test_isTemplatesDirectory_returnsFalseWithNoVault() {
        let state = AppState()
        let someURL = URL(fileURLWithPath: "/tmp/templates")
        XCTAssertFalse(state.isTemplatesDirectory(someURL),
                       "isTemplatesDirectory should be false when no vault is open")
    }
}
