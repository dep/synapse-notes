import XCTest
@testable import Synapse

/// Tests for SettingsManager.parsedExtensions with bare (non-glob) extension patterns.
/// The filter supports both "*.md" glob syntax and bare "md" format — this file
/// specifically covers the bare-extension code path which existing tests skip.
final class SettingsManagerBareExtensionsTests: XCTestCase {

    var sut: SettingsManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent("settings.json").path
        sut = SettingsManager(configPath: configPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - parsedExtensions: bare format

    func test_parsedExtensions_singleBareExtension() {
        sut.fileExtensionFilter = "md"
        XCTAssertEqual(sut.parsedExtensions, ["md"])
    }

    func test_parsedExtensions_multipleBareExtensions() {
        sut.fileExtensionFilter = "md, txt"
        XCTAssertEqual(sut.parsedExtensions.sorted(), ["md", "txt"])
    }

    func test_parsedExtensions_bareExtensionIsLowercased() {
        sut.fileExtensionFilter = "MD"
        XCTAssertEqual(sut.parsedExtensions, ["md"])
    }

    func test_parsedExtensions_mixedGlobAndBareFormat() {
        sut.fileExtensionFilter = "*.md, txt, *.swift"
        XCTAssertEqual(sut.parsedExtensions.sorted(), ["md", "swift", "txt"])
    }

    func test_parsedExtensions_bareExtensionWithExtraWhitespace() {
        sut.fileExtensionFilter = "  md  ,  txt  "
        XCTAssertEqual(sut.parsedExtensions.sorted(), ["md", "txt"])
    }

    func test_parsedExtensions_dotPrefixedBareExtension_treatedAsBareName() {
        // ".md" does not start with "*.", so it falls through to the bare-extension path.
        // The parsed extension is ".md" (not "md"), which would not match files via pathExtension.
        sut.fileExtensionFilter = ".md"
        XCTAssertEqual(sut.parsedExtensions, [".md"])
    }

    // MARK: - shouldShowFile with bare extensions

    func test_shouldShowFile_bareExtension_matchesCorrectly() {
        sut.fileExtensionFilter = "md"
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let txtFile = URL(fileURLWithPath: "/test/note.txt")
        XCTAssertTrue(sut.shouldShowFile(mdFile), "Should show .md files with bare 'md' filter")
        XCTAssertFalse(sut.shouldShowFile(txtFile), "Should not show .txt with bare 'md' filter")
    }

    func test_shouldShowFile_multipleBareExtensions_matchesBoth() {
        sut.fileExtensionFilter = "md, txt"
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let txtFile = URL(fileURLWithPath: "/test/note.txt")
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")
        XCTAssertTrue(sut.shouldShowFile(mdFile))
        XCTAssertTrue(sut.shouldShowFile(txtFile))
        XCTAssertFalse(sut.shouldShowFile(swiftFile))
    }

    func test_shouldShowFile_bareExtension_isCaseInsensitive() {
        sut.fileExtensionFilter = "md"
        let upperFile = URL(fileURLWithPath: "/test/note.MD")
        XCTAssertTrue(sut.shouldShowFile(upperFile), "Bare extension filter should be case-insensitive")
    }

    func test_shouldShowFile_mixedFormat_matchesFilesForBothGlobAndBare() {
        sut.fileExtensionFilter = "*.swift, md"
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let txtFile = URL(fileURLWithPath: "/test/note.txt")
        XCTAssertTrue(sut.shouldShowFile(swiftFile))
        XCTAssertTrue(sut.shouldShowFile(mdFile))
        XCTAssertFalse(sut.shouldShowFile(txtFile))
    }
}
