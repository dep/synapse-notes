import XCTest
@testable import Synapse

/// Tests for FileBrowserError: error descriptions shown in the file browser UI
/// when operations like create, rename, or delete fail.
final class FileBrowserErrorTests: XCTestCase {

    // MARK: - errorDescription

    func test_noWorkspace_errorDescription() {
        XCTAssertEqual(
            FileBrowserError.noWorkspace.errorDescription,
            "Open a folder before managing files."
        )
    }

    func test_invalidName_errorDescription() {
        XCTAssertEqual(
            FileBrowserError.invalidName.errorDescription,
            "Enter a valid name."
        )
    }

    func test_itemAlreadyExists_includesFilenameInDescription() {
        let error = FileBrowserError.itemAlreadyExists("My Note.md")
        XCTAssertEqual(error.errorDescription, "My Note.md already exists.")
    }

    func test_itemAlreadyExists_differentFileName_includesThatName() {
        let error = FileBrowserError.itemAlreadyExists("archive/old-note.md")
        XCTAssertTrue(
            error.errorDescription?.contains("archive/old-note.md") ?? false,
            "Error description should include the conflicting item name"
        )
        XCTAssertTrue(
            error.errorDescription?.contains("already exists") ?? false
        )
    }

    func test_operationFailed_returnsProvidedMessage() {
        let message = "Could not create the note."
        XCTAssertEqual(FileBrowserError.operationFailed(message).errorDescription, message)
    }

    func test_operationFailed_differentMessage_preservesMessageVerbatim() {
        let message = "The disk is full."
        XCTAssertEqual(FileBrowserError.operationFailed(message).errorDescription, message)
    }

    func test_operationFailed_emptyMessage_returnsEmptyString() {
        XCTAssertEqual(FileBrowserError.operationFailed("").errorDescription, "")
    }

    // MARK: - errorDescription is non-nil for all cases

    func test_allCases_haveNonNilErrorDescription() {
        let errors: [FileBrowserError] = [
            .noWorkspace,
            .invalidName,
            .itemAlreadyExists("file.md"),
            .operationFailed("error")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a non-nil errorDescription")
        }
    }

    // MARK: - Equatable

    func test_noWorkspace_equalToItself() {
        XCTAssertEqual(FileBrowserError.noWorkspace, FileBrowserError.noWorkspace)
    }

    func test_invalidName_equalToItself() {
        XCTAssertEqual(FileBrowserError.invalidName, FileBrowserError.invalidName)
    }

    func test_itemAlreadyExists_sameFilename_isEqual() {
        XCTAssertEqual(
            FileBrowserError.itemAlreadyExists("file.md"),
            FileBrowserError.itemAlreadyExists("file.md")
        )
    }

    func test_itemAlreadyExists_differentFilenames_areNotEqual() {
        XCTAssertNotEqual(
            FileBrowserError.itemAlreadyExists("a.md"),
            FileBrowserError.itemAlreadyExists("b.md")
        )
    }

    func test_operationFailed_sameMessage_isEqual() {
        XCTAssertEqual(
            FileBrowserError.operationFailed("error"),
            FileBrowserError.operationFailed("error")
        )
    }

    func test_operationFailed_differentMessages_areNotEqual() {
        XCTAssertNotEqual(
            FileBrowserError.operationFailed("error one"),
            FileBrowserError.operationFailed("error two")
        )
    }

    func test_noWorkspace_notEqualToInvalidName() {
        XCTAssertNotEqual(FileBrowserError.noWorkspace, FileBrowserError.invalidName)
    }

    func test_invalidName_notEqualToOperationFailed() {
        XCTAssertNotEqual(
            FileBrowserError.invalidName,
            FileBrowserError.operationFailed("error")
        )
    }

    func test_noWorkspace_notEqualToItemAlreadyExists() {
        XCTAssertNotEqual(
            FileBrowserError.noWorkspace,
            FileBrowserError.itemAlreadyExists("file.md")
        )
    }

    // MARK: - Additional coverage: different names produce different descriptions

    func test_itemAlreadyExists_differentNames_produceDifferentDescriptions() {
        let desc1 = FileBrowserError.itemAlreadyExists("alpha.md").errorDescription!
        let desc2 = FileBrowserError.itemAlreadyExists("beta.md").errorDescription!
        XCTAssertNotEqual(desc1, desc2,
                          "Different item names must produce different error descriptions")
    }

    func test_noWorkspace_errorDescription_isSentenceLike() {
        let desc = FileBrowserError.noWorkspace.errorDescription!
        XCTAssertGreaterThanOrEqual(desc.count, 5,
                                    "noWorkspace error description should be a meaningful sentence")
    }

    func test_operationFailed_doesNotMutateMessage() {
        let message = "Unexpected I/O error at path: /tmp/foo.md"
        let error = FileBrowserError.operationFailed(message)
        XCTAssertEqual(error.errorDescription, message,
                       "operationFailed must return the message verbatim, without modification")
    }
}
