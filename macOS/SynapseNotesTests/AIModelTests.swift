import XCTest
@testable import Synapse

final class AIModelTests: XCTestCase {
    func test_apiIDs_areExactAnthropicModelStrings() {
        XCTAssertEqual(AIModel.haiku.apiID, "claude-haiku-4-5")
        XCTAssertEqual(AIModel.sonnet.apiID, "claude-sonnet-4-6")
        XCTAssertEqual(AIModel.opus.apiID, "claude-opus-4-8")
    }

    func test_displayNames_areHumanReadable() {
        XCTAssertEqual(AIModel.haiku.displayName, "Haiku 4.5")
        XCTAssertEqual(AIModel.sonnet.displayName, "Sonnet 4.6")
        XCTAssertEqual(AIModel.opus.displayName, "Opus 4.8")
    }

    func test_initFromAPIID_roundTrips_andDefaultsToSonnetOnUnknown() {
        XCTAssertEqual(AIModel(apiID: "claude-opus-4-8"), .opus)
        XCTAssertEqual(AIModel(apiID: "garbage"), .sonnet)
    }

    func test_defaultModel_isSonnet() {
        XCTAssertEqual(AIModel.default, .sonnet)
    }
}
