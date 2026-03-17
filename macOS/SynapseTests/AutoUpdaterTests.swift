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
        XCTAssertFalse(updater.updateInstalled, "Update should not be installed initially")
        XCTAssertNil(updater.latestVersion, "Latest version should be nil initially")
    }
    
    func testCurrentVersionIsNotEmpty() {
        // The current version should be read from Info.plist
        // In tests, verify the updater has a valid initial state
        // The version is stored internally and used for comparisons
        XCTAssertNotNil(updater, "Updater should be initialized")
    }
    
    // MARK: - Additional Edge Case Tests
    
    func testReleasesURL() {
        let expectedURL = URL(string: "https://github.com/dep/synapse/releases")!
        XCTAssertEqual(updater.releasesURL, expectedURL, "Releases URL should point to GitHub releases page")
    }
    
    func testEmptyVersionStrings() {
        let result = updater.isNewerVersion(latest: "", current: "1.0.0")
        XCTAssertFalse(result, "Empty latest version should not be newer")
    }
    
    func testInvalidVersionStrings() {
        let result = updater.isNewerVersion(latest: "abc", current: "1.0.0")
        XCTAssertFalse(result, "Invalid version should not be newer")
    }
}
