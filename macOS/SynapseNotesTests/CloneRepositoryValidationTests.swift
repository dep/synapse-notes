import XCTest
@testable import Synapse

/// Tests when the Clone button is enabled on the welcome / folder picker sheet.
final class CloneRepositoryValidationTests: XCTestCase {

    func test_canClone_requiresNonEmptyRemoteAndDestination() {
        let dest = URL(fileURLWithPath: "/tmp/clone-here")
        XCTAssertTrue(CloneRepositoryValidation.canClone(remoteURL: "https://github.com/a/b.git", destinationURL: dest))
    }

    func test_canClone_falseWhenRemoteWhitespaceOnly() {
        let dest = URL(fileURLWithPath: "/tmp/clone-here")
        XCTAssertFalse(CloneRepositoryValidation.canClone(remoteURL: "  \n", destinationURL: dest))
    }

    func test_canClone_falseWhenNoDestination() {
        XCTAssertFalse(CloneRepositoryValidation.canClone(remoteURL: "https://github.com/a/b.git", destinationURL: nil))
    }

    func test_canClone_falseWhenBothMissing() {
        XCTAssertFalse(CloneRepositoryValidation.canClone(remoteURL: "", destinationURL: nil))
    }
}
