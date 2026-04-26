import XCTest
@testable import Synapse

/// Ensures AppState keeps `VaultIndex` in sync for tag/folder recency — sidebar and state restore depend on this.
final class VaultIndexRecencyMirrorTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func test_openTagInNewTab_mirrorsRecentTagsToVaultIndex() {
        sut.openTagInNewTab("work")
        XCTAssertEqual(sut.recentTags, ["work"])
        XCTAssertEqual(sut.vaultIndex.recentTags, sut.recentTags)

        sut.openTagInNewTab("ideas")
        XCTAssertEqual(sut.recentTags, ["ideas", "work"])
        XCTAssertEqual(sut.vaultIndex.recentTags, sut.recentTags)
    }

    func test_expandAndScrollToFolder_mirrorsRecentFoldersToVaultIndex() {
        let folder = tempDir.appendingPathComponent("Projects", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        sut.expandAndScrollToFolder(folder)
        XCTAssertEqual(sut.recentFolders, [folder])
        XCTAssertEqual(sut.vaultIndex.recentFolders, sut.recentFolders)

        let other = tempDir.appendingPathComponent("Archive", isDirectory: true)
        try! FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        sut.expandAndScrollToFolder(other)
        XCTAssertEqual(sut.recentFolders, [other, folder])
        XCTAssertEqual(sut.vaultIndex.recentFolders, sut.recentFolders)
    }
}
