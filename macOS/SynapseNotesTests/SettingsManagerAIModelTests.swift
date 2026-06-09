import XCTest
@testable import Synapse

final class SettingsManagerAIModelTests: XCTestCase {
    private var tempDir: URL!
    private var globalPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        globalPath = tempDir.appendingPathComponent("global.yml").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_default_isSonnetAPIID() {
        let mgr = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        XCTAssertEqual(mgr.aiDefaultModel, "claude-sonnet-4-6")
    }

    func test_aiDefaultModel_persistsAcrossReload() {
        let mgr = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        mgr.aiDefaultModel = "claude-opus-4-8"
        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        XCTAssertEqual(reloaded.aiDefaultModel, "claude-opus-4-8")
    }
}
