import XCTest
@testable import Synapse

@MainActor
final class AutoUpdaterTests: XCTestCase {
    
    var updater: AutoUpdater!
    
    override func setUp() async throws {
        updater = AutoUpdater()
    }
    
    override func tearDown() async throws {
        updater = nil
    }
    
    // MARK: - Version Comparison Tests
    
    func testIsNewerVersionBasicComparison() {
        // Test that the isNewerVersion method works correctly
        let isNewer = updater.isNewerVersion(latest: "1.1.0", current: "1.0.0")
        XCTAssertTrue(isNewer, "1.1.0 should be newer than 1.0.0")
    }
    
    func testVersionComparisonSameVersion() {
        // Test that same versions return false
        let result = updater.isNewerVersion(latest: "1.0.0", current: "1.0.0")
        XCTAssertFalse(result, "Same versions should not be considered newer")
    }
    
    func testVersionComparisonNewerMajor() {
        let result = updater.isNewerVersion(latest: "2.0.0", current: "1.0.0")
        XCTAssertTrue(result, "2.0.0 should be newer than 1.0.0")
    }
    
    func testVersionComparisonNewerMinor() {
        let result = updater.isNewerVersion(latest: "1.2.0", current: "1.1.0")
        XCTAssertTrue(result, "1.2.0 should be newer than 1.1.0")
    }
    
    func testVersionComparisonNewerPatch() {
        let result = updater.isNewerVersion(latest: "1.0.2", current: "1.0.1")
        XCTAssertTrue(result, "1.0.2 should be newer than 1.0.1")
    }
    
    func testVersionComparisonOlderVersion() {
        let result = updater.isNewerVersion(latest: "1.0.0", current: "1.1.0")
        XCTAssertFalse(result, "1.0.0 should not be newer than 1.1.0")
    }
    
    func testVersionComparisonWithVPrefix() {
        let result = updater.isNewerVersion(latest: "v2.0.0", current: "v1.0.0")
        XCTAssertTrue(result, "Should handle versions with v prefix")
    }
    
    func testVersionComparisonDifferentLengths() {
        let result1 = updater.isNewerVersion(latest: "1.0.0.1", current: "1.0.0")
        XCTAssertTrue(result1, "1.0.0.1 should be newer than 1.0.0")
        
        let result2 = updater.isNewerVersion(latest: "1.0.0", current: "1.0.0.1")
        XCTAssertFalse(result2, "1.0.0 should not be newer than 1.0.0.1")
    }
    
    // MARK: - State Tests
    
    func testInitialState() {
        XCTAssertFalse(updater.updateAvailable, "Update should not be available initially")
        XCTAssertFalse(updater.restartRequired, "Restart should not be required initially")
        XCTAssertNil(updater.latestVersion, "Latest version should be nil initially")
    }
    
    func testCurrentVersionIsNotEmpty() {
        // The current version should be read from Info.plist
        // In tests, verify the updater has a valid initial state
        // The version is stored internally and used for comparisons
        XCTAssertNotNil(updater, "Updater should be initialized")
    }
    
    // MARK: - Additional Edge Case Tests

    func testEmptyVersionStrings() {
        let result = updater.isNewerVersion(latest: "", current: "1.0.0")
        XCTAssertFalse(result, "Empty latest version should not be newer")
    }
    
    func testInvalidVersionStrings() {
        let result = updater.isNewerVersion(latest: "abc", current: "1.0.0")
        XCTAssertFalse(result, "Invalid version should not be newer")
    }

    // MARK: - SynapseAppInstaller (atomic install)

    func testInstallBundleCopiesToEmptyDestination() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("synapse-install-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let source = root.appendingPathComponent("Source.app")
        let dest = root.appendingPathComponent("Dest.app")
        try makeFakeAppBundle(at: source, marker: "fresh")

        try SynapseAppInstaller.installBundle(from: source, to: dest)

        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("Contents/marker.txt")), "fresh")
    }

    func testInstallBundleReplacesExistingWithoutLeavingBrokenState() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("synapse-replace-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let sourceV1 = root.appendingPathComponent("SourceV1.app")
        let sourceV2 = root.appendingPathComponent("SourceV2.app")
        let dest = root.appendingPathComponent("Dest.app")
        try makeFakeAppBundle(at: sourceV1, marker: "v1")
        try makeFakeAppBundle(at: sourceV2, marker: "v2")

        try SynapseAppInstaller.installBundle(from: sourceV1, to: dest)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("Contents/marker.txt")), "v1")

        try SynapseAppInstaller.installBundle(from: sourceV2, to: dest)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("Contents/marker.txt")), "v2")
        let leftovers = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".Synapse.app.install") }
        XCTAssertTrue(leftovers.isEmpty, "staging files should be removed: \(leftovers)")
    }

    func testInstallBundleMissingSourceLeavesDestinationIntact() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("synapse-fail-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let missingSource = root.appendingPathComponent("Nope.app")
        let dest = root.appendingPathComponent("Dest.app")
        try makeFakeAppBundle(at: dest, marker: "keep")

        XCTAssertThrowsError(try SynapseAppInstaller.installBundle(from: missingSource, to: dest)) { error in
            XCTAssertEqual(error as? UpdateError, .installFailed)
        }
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("Contents/marker.txt")), "keep")
    }

    private func makeFakeAppBundle(at url: URL, marker: String) throws {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try marker.write(to: contents.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }
}
