import XCTest
@testable import Noted

/// Tests for `FileBrowserError` — the error type surfaced to the user whenever a
/// file-system operation fails. Every `errorDescription` is displayed directly in the
/// UI, so correctness matters for UX.
final class FileBrowserErrorTests: XCTestCase {

    // MARK: - errorDescription: noWorkspace

    func test_errorDescription_noWorkspace_isNonEmpty() {
        let description = FileBrowserError.noWorkspace.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty, "noWorkspace errorDescription must not be nil or empty")
    }

    func test_errorDescription_noWorkspace_mentionsOpenOrFolder() {
        let description = FileBrowserError.noWorkspace.errorDescription ?? ""
        let lower = description.lowercased()
        XCTAssertTrue(
            lower.contains("open") || lower.contains("folder"),
            "noWorkspace description should guide the user to open a folder, got: \(description)"
        )
    }

    // MARK: - errorDescription: invalidName

    func test_errorDescription_invalidName_isNonEmpty() {
        let description = FileBrowserError.invalidName.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty, "invalidName errorDescription must not be nil or empty")
    }

    func test_errorDescription_invalidName_mentionsNameOrValid() {
        let description = FileBrowserError.invalidName.errorDescription ?? ""
        let lower = description.lowercased()
        XCTAssertTrue(
            lower.contains("name") || lower.contains("valid"),
            "invalidName description should reference a valid name, got: \(description)"
        )
    }

    // MARK: - errorDescription: itemAlreadyExists

    func test_errorDescription_itemAlreadyExists_containsItemName() {
        let description = FileBrowserError.itemAlreadyExists("my-note.md").errorDescription ?? ""
        XCTAssertTrue(
            description.contains("my-note.md"),
            "itemAlreadyExists description must include the conflicting item name, got: \(description)"
        )
    }

    func test_errorDescription_itemAlreadyExists_mentionsExistsOrAlready() {
        let description = FileBrowserError.itemAlreadyExists("folder").errorDescription ?? ""
        let lower = description.lowercased()
        XCTAssertTrue(
            lower.contains("exist") || lower.contains("already"),
            "itemAlreadyExists description should state the item already exists, got: \(description)"
        )
    }

    func test_errorDescription_itemAlreadyExists_withDifferentNames_reflectsThatName() {
        let descA = FileBrowserError.itemAlreadyExists("alpha.md").errorDescription ?? ""
        let descB = FileBrowserError.itemAlreadyExists("beta.md").errorDescription ?? ""
        XCTAssertTrue(descA.contains("alpha.md"))
        XCTAssertTrue(descB.contains("beta.md"))
        XCTAssertFalse(descA.contains("beta.md"), "Each description must reference its own item name")
    }

    // MARK: - errorDescription: operationFailed

    func test_errorDescription_operationFailed_returnsExactProvidedMessage() {
        let message = "Could not write to the disk."
        XCTAssertEqual(FileBrowserError.operationFailed(message).errorDescription, message)
    }

    func test_errorDescription_operationFailed_emptyMessage_returnsEmptyString() {
        XCTAssertEqual(FileBrowserError.operationFailed("").errorDescription, "")
    }

    // MARK: - Equatable

    func test_equatable_sameNoWorkspace_areEqual() {
        XCTAssertEqual(FileBrowserError.noWorkspace, FileBrowserError.noWorkspace)
    }

    func test_equatable_sameInvalidName_areEqual() {
        XCTAssertEqual(FileBrowserError.invalidName, FileBrowserError.invalidName)
    }

    func test_equatable_itemAlreadyExists_sameName_areEqual() {
        XCTAssertEqual(
            FileBrowserError.itemAlreadyExists("test.md"),
            FileBrowserError.itemAlreadyExists("test.md")
        )
    }

    func test_equatable_itemAlreadyExists_differentNames_areNotEqual() {
        XCTAssertNotEqual(
            FileBrowserError.itemAlreadyExists("a.md"),
            FileBrowserError.itemAlreadyExists("b.md")
        )
    }

    func test_equatable_operationFailed_sameMessage_areEqual() {
        XCTAssertEqual(
            FileBrowserError.operationFailed("err"),
            FileBrowserError.operationFailed("err")
        )
    }

    func test_equatable_operationFailed_differentMessages_areNotEqual() {
        XCTAssertNotEqual(
            FileBrowserError.operationFailed("err1"),
            FileBrowserError.operationFailed("err2")
        )
    }

    func test_equatable_differentCases_areNotEqual() {
        XCTAssertNotEqual(FileBrowserError.noWorkspace, FileBrowserError.invalidName)
        XCTAssertNotEqual(FileBrowserError.invalidName, FileBrowserError.itemAlreadyExists("x"))
        XCTAssertNotEqual(FileBrowserError.noWorkspace, FileBrowserError.operationFailed(""))
    }
}
