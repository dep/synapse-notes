import XCTest
@testable import Synapse

/// Tests for `FolderAppearance.resolvedColor` and `resolvedSymbolName` when keys are missing or unknown.
final class FolderAppearanceResolvedPropertiesTests: XCTestCase {

    func test_resolvedColor_nilForUnknownColorKey() {
        let sut = FolderAppearance(relativePath: "x", colorKey: "not-a-palette-id", iconKey: nil)
        XCTAssertNil(sut.resolvedColor)
    }

    func test_resolvedSymbolName_nilForUnknownIconKey() {
        let sut = FolderAppearance(relativePath: "x", colorKey: nil, iconKey: "not-an-icon-id")
        XCTAssertNil(sut.resolvedSymbolName)
    }

    func test_resolvedProperties_bothNilWhenKeysNil() {
        let sut = FolderAppearance(relativePath: "Notes", colorKey: nil, iconKey: nil)
        XCTAssertNil(sut.resolvedColor)
        XCTAssertNil(sut.resolvedSymbolName)
    }
}
