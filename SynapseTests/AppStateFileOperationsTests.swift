import XCTest
@testable import Synapse

/// Tests for file and folder CRUD operations: createNote, createFolder,
/// renameItem, deleteItem — including all validation and error paths.
final class AppStateFileOperationsTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - FileBrowserError descriptions

    func test_error_noWorkspace_description() {
        XCTAssertEqual(FileBrowserError.noWorkspace.errorDescription,
                       "Open a folder before managing files.")
    }

    func test_error_invalidName_description() {
        XCTAssertEqual(FileBrowserError.invalidName.errorDescription, "Enter a valid name.")
    }

    func test_error_itemAlreadyExists_description() {
        XCTAssertEqual(FileBrowserError.itemAlreadyExists("foo.md").errorDescription,
                       "foo.md already exists.")
    }

    func test_error_operationFailed_description() {
        XCTAssertEqual(FileBrowserError.operationFailed("Boom").errorDescription, "Boom")
    }

    // MARK: - createNote: valid inputs

    func test_createNote_validName_createsFile() throws {
        let url = try sut.createNote(named: "MyNote")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "MyNote.md")
    }

    func test_createNote_nameWithExtension_doesNotDoubleExtend() throws {
        let url = try sut.createNote(named: "MyNote.md")
        XCTAssertEqual(url.lastPathComponent, "MyNote.md")
    }

    func test_createNote_slashSanitized_toDash() throws {
        let url = try sut.createNote(named: "path/to/note")
        XCTAssertEqual(url.lastPathComponent, "path-to-note.md")
    }

    func test_createNote_selectsCreatedFile() throws {
        let url = try sut.createNote(named: "NewNote")
        XCTAssertEqual(sut.selectedFile, url)
    }

    func test_createNote_appearsInAllFiles() throws {
        try sut.createNote(named: "Listed")
        XCTAssertTrue(sut.allFiles.contains { $0.lastPathComponent == "Listed.md" })
    }

    // MARK: - createNote: invalid inputs

    func test_createNote_emptyName_throwsInvalidName() {
        XCTAssertThrowsError(try sut.createNote(named: "")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_createNote_whitespaceOnly_throwsInvalidName() {
        XCTAssertThrowsError(try sut.createNote(named: "   ")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_createNote_dotName_throwsInvalidName() {
        XCTAssertThrowsError(try sut.createNote(named: ".")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_createNote_dotDotName_throwsInvalidName() {
        XCTAssertThrowsError(try sut.createNote(named: "..")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_createNote_duplicate_throwsItemAlreadyExists() throws {
        try sut.createNote(named: "Duplicate")
        XCTAssertThrowsError(try sut.createNote(named: "Duplicate")) { error in
            if case .itemAlreadyExists = error as? FileBrowserError { return }
            XCTFail("Expected .itemAlreadyExists, got \(error)")
        }
    }

    func test_createNote_withoutWorkspace_throwsNoWorkspace() {
        sut.rootURL = nil
        XCTAssertThrowsError(try sut.createNote(named: "AnyNote")) { error in
            XCTAssertEqual(error as? FileBrowserError, .noWorkspace)
        }
    }

    // MARK: - createFolder

    func test_createFolder_validName_createsDirectory() throws {
        let url = try sut.createFolder(named: "MyFolder")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func test_createFolder_emptyName_throwsInvalidName() {
        XCTAssertThrowsError(try sut.createFolder(named: "")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }

    func test_createFolder_duplicate_throwsItemAlreadyExists() throws {
        try sut.createFolder(named: "FolderA")
        XCTAssertThrowsError(try sut.createFolder(named: "FolderA")) { error in
            if case .itemAlreadyExists = error as? FileBrowserError { return }
            XCTFail("Expected .itemAlreadyExists, got \(error)")
        }
    }

    func test_createFolder_withoutWorkspace_throwsNoWorkspace() {
        sut.rootURL = nil
        XCTAssertThrowsError(try sut.createFolder(named: "Folder")) { error in
            XCTAssertEqual(error as? FileBrowserError, .noWorkspace)
        }
    }

    // MARK: - deleteItem

    func test_deleteItem_removesFileFromDisk() throws {
        let url = try sut.createNote(named: "ToDelete")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try sut.deleteItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_deleteItem_clearsSelectionWhenSelectedFileDeleted() throws {
        let url = try sut.createNote(named: "Selected")
        sut.openFile(url)
        XCTAssertEqual(sut.selectedFile, url)

        try sut.deleteItem(at: url)

        XCTAssertNil(sut.selectedFile)
        XCTAssertEqual(sut.fileContent, "")
        XCTAssertFalse(sut.isDirty)
    }

    func test_deleteItem_removesFileFromAllFiles() throws {
        let url = try sut.createNote(named: "WillBeGone")
        XCTAssertTrue(sut.allFiles.contains(url))
        try sut.deleteItem(at: url)
        XCTAssertFalse(sut.allFiles.contains(url))
    }

    // MARK: - renameItem

    func test_renameItem_movesFile() throws {
        let url = try sut.createNote(named: "OldName")
        let newURL = try sut.renameItem(at: url, to: "NewName")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(newURL.lastPathComponent, "NewName.md")
    }

    func test_renameItem_sameNameReturnsOriginalURL() throws {
        let url = try sut.createNote(named: "SameName")
        let result = try sut.renameItem(at: url, to: "SameName.md")
        XCTAssertEqual(result, url)
    }

    func test_renameItem_updatesSelectedFile() throws {
        let url = try sut.createNote(named: "BeforeRename")
        sut.openFile(url)
        let newURL = try sut.renameItem(at: url, to: "AfterRename")
        XCTAssertEqual(sut.selectedFile, newURL)
    }

    func test_renameItem_emptyName_throwsInvalidName() throws {
        let url = try sut.createNote(named: "ToRename")
        XCTAssertThrowsError(try sut.renameItem(at: url, to: "")) { error in
            XCTAssertEqual(error as? FileBrowserError, .invalidName)
        }
    }
}
