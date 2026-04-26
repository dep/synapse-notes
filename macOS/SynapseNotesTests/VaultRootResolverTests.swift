import XCTest
@testable import Synapse

/// Tests vault root resolution when opening files or folders from Finder (critical for correct workspace scope).
final class VaultRootResolverTests: XCTestCase {

    var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultRootResolverTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func test_fileInsideNestedVault_returnsAncestorWithSynapseMarker() {
        let vault = tempRoot.appendingPathComponent("myvault", isDirectory: true)
        let notes = vault.appendingPathComponent("notes", isDirectory: true)
        try! FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".synapse", isDirectory: true),
            withIntermediateDirectories: true
        )
        let fileURL = notes.appendingPathComponent("hello.md")
        try! "x".write(to: fileURL, atomically: true, encoding: .utf8)

        let root = VaultRootResolver.vaultRoot(for: fileURL)
        XCTAssertEqual(root.standardizedFileURL.path, vault.standardizedFileURL.path)
    }

    func test_directoryThatIsVaultRoot_returnsSelf() {
        let vault = tempRoot.appendingPathComponent("rootvault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".synapse", isDirectory: true),
            withIntermediateDirectories: true
        )

        let root = VaultRootResolver.vaultRoot(for: vault)
        XCTAssertEqual(root.standardizedFileURL.path, vault.standardizedFileURL.path)
    }

    func test_legacyVault_fileWithoutSynapseMarker_returnsFileParent() {
        let folder = tempRoot.appendingPathComponent("legacy", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("note.md")
        try! "x".write(to: fileURL, atomically: true, encoding: .utf8)

        let root = VaultRootResolver.vaultRoot(for: fileURL)
        XCTAssertEqual(root.standardizedFileURL.path, folder.standardizedFileURL.path)
    }

    func test_legacyVault_plainDirectory_returnsSelf() {
        let folder = tempRoot.appendingPathComponent("plain", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let root = VaultRootResolver.vaultRoot(for: folder)
        XCTAssertEqual(root.standardizedFileURL.path, folder.standardizedFileURL.path)
    }
}
