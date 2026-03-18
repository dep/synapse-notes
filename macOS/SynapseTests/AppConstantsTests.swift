import XCTest
@testable import Synapse

/// Tests for AppConstants values.
///
/// These constants define the vault directory structure, file naming conventions,
/// and numeric limits relied on throughout the app.  A silent change to any of
/// these values would corrupt persisted data or break core features, so pinning
/// them with explicit assertions acts as a regression safety-net.
final class AppConstantsTests: XCTestCase {

    // MARK: - Directory / filename constants

    func test_vaultConfigDirectory_isExpectedValue() {
        XCTAssertEqual(AppConstants.vaultConfigDirectory, ".noted",
                       "Changing this breaks vault settings discovery")
    }

    func test_imagesPasteDirectory_isExpectedValue() {
        XCTAssertEqual(AppConstants.imagesPasteDirectory, ".images",
                       "Changing this breaks image-paste storage")
    }

    func test_defaultTemplatesDirectory_isExpectedValue() {
        XCTAssertEqual(AppConstants.defaultTemplatesDirectory, "templates")
    }

    func test_defaultDailyNotesFolder_isExpectedValue() {
        XCTAssertEqual(AppConstants.defaultDailyNotesFolder, "daily")
    }

    func test_settingsFilename_isExpectedValue() {
        XCTAssertEqual(AppConstants.settingsFilename, "settings.yml",
                       "Changing this breaks settings persistence")
    }

    // MARK: - Git defaults

    func test_defaultBranchName_isMain() {
        XCTAssertEqual(AppConstants.defaultBranchName, "main",
                       "Default git branch name must stay 'main'")
    }

    func test_gitSearchPaths_containsUsrBinGit() {
        XCTAssertTrue(AppConstants.gitSearchPaths.contains("/usr/bin/git"),
                      "Must include the Xcode CLT git path")
    }

    func test_gitSearchPaths_containsHomebrewPath() {
        XCTAssertTrue(AppConstants.gitSearchPaths.contains("/opt/homebrew/bin/git"),
                      "Must include the Apple-Silicon Homebrew git path")
    }

    func test_gitSearchPaths_containsLocalBinGit() {
        XCTAssertTrue(AppConstants.gitSearchPaths.contains("/usr/local/bin/git"),
                      "Must include the Intel Homebrew git path")
    }

    func test_gitSearchPaths_isNonEmpty() {
        XCTAssertFalse(AppConstants.gitSearchPaths.isEmpty)
    }

    // MARK: - File extension filter

    func test_defaultFileExtensionFilter_includesMd() {
        XCTAssertTrue(AppConstants.defaultFileExtensionFilter.contains("*.md"))
    }

    func test_defaultFileExtensionFilter_includesTxt() {
        XCTAssertTrue(AppConstants.defaultFileExtensionFilter.contains("*.txt"))
    }

    // MARK: - Numeric limits

    func test_maxRecentFiles_isFortyOrGreater() {
        XCTAssertGreaterThanOrEqual(AppConstants.maxRecentFiles, 40,
                                    "Must cache at least 40 recent files")
    }

    func test_maxRecentFiles_isReasonable() {
        XCTAssertLessThanOrEqual(AppConstants.maxRecentFiles, 200,
                                 "Caching too many recent files wastes memory")
    }

    func test_maxSearchMatches_isPositive() {
        XCTAssertGreaterThan(AppConstants.maxSearchMatches, 0)
    }

    func test_maxSearchMatches_is2000() {
        XCTAssertEqual(AppConstants.maxSearchMatches, 2000)
    }

    func test_maxLinkTokenLength_isPositive() {
        XCTAssertGreaterThan(AppConstants.maxLinkTokenLength, 0)
    }

    func test_maxLinkTokenLength_is120() {
        XCTAssertEqual(AppConstants.maxLinkTokenLength, 120)
    }

    // MARK: - Fallback URL

    func test_unsavedFileURL_isMarkdownFile() {
        XCTAssertEqual(AppConstants.unsavedFileURL.pathExtension, "md",
                       "Fallback URL must be a .md file")
    }

    func test_unsavedFileURL_isInTmp() {
        XCTAssertTrue(AppConstants.unsavedFileURL.path.hasPrefix("/tmp"),
                      "Fallback URL should live in /tmp")
    }
}
