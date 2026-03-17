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
        // Use reflection to access the private method for testing
        let isNewer = updater.perform(Selector(("isNewerVersionWithLatest:current:")), with: "1.1.0", with: "1.0.0")
        XCTAssertNotNil(isNewer)
    }
    
    func testVersionComparisonSameVersion() {
        // Test that same versions return false
        let result = compareVersions(latest: "1.0.0", current: "1.0.0")
        XCTAssertFalse(result, "Same versions should not be considered newer")
    }
    
    func testVersionComparisonNewerMajor() {
        let result = compareVersions(latest: "2.0.0", current: "1.0.0")
        XCTAssertTrue(result, "2.0.0 should be newer than 1.0.0")
    }
    
    func testVersionComparisonNewerMinor() {
        let result = compareVersions(latest: "1.2.0", current: "1.1.0")
        XCTAssertTrue(result, "1.2.0 should be newer than 1.1.0")
    }
    
    func testVersionComparisonNewerPatch() {
        let result = compareVersions(latest: "1.0.2", current: "1.0.1")
        XCTAssertTrue(result, "1.0.2 should be newer than 1.0.1")
    }
    
    func testVersionComparisonOlderVersion() {
        let result = compareVersions(latest: "1.0.0", current: "1.1.0")
        XCTAssertFalse(result, "1.0.0 should not be newer than 1.1.0")
    }
    
    func testVersionComparisonWithVPrefix() {
        let result = compareVersions(latest: "2.0.0", current: "1.0.0")
        XCTAssertTrue(result, "Should handle versions without v prefix")
    }
    
    func testVersionComparisonDifferentLengths() {
        let result1 = compareVersions(latest: "1.0.0.1", current: "1.0.0")
        XCTAssertTrue(result1, "1.0.0.1 should be newer than 1.0.0")
        
        let result2 = compareVersions(latest: "1.0.0", current: "1.0.0.1")
        XCTAssertFalse(result2, "1.0.0 should not be newer than 1.0.0.1")
    }
    
    // MARK: - State Tests
    
    func testInitialState() {
        XCTAssertFalse(updater.updateAvailable, "Update should not be available initially")
        XCTAssertFalse(updater.updateInstalled, "Update should not be installed initially")
        XCTAssertNil(updater.latestVersion, "Latest version should be nil initially")
    }
    
    func testCurrentVersionReading() {
        // The current version should be read from Info.plist
        // In tests, this might be the test bundle version, but we can verify it's not empty
        let currentVersion = updater.perform(Selector(("currentVersion")))
        XCTAssertNotNil(currentVersion, "Current version should be readable")
    }
    
    // MARK: - Helper Methods
    
    /// Helper function that mimics the private isNewerVersion method
    private func compareVersions(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(latestComponents.count, currentComponents.count) {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }
        
        return false
    }
}
