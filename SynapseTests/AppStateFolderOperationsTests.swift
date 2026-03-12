import XCTest
@testable import Synapse

/// Tests for folder-level rename and delete operations, focusing on how
/// AppState updates selectedFile and navigation history when the folder
/// *containing* the selected file is moved or removed.
final class AppStateFolderOperationsTests: XCTestCase {

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

    // MARK: - Helpers

    private func makeSubfolder(named name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeFile(in folder: URL, named name: String, content: String = "") -> URL {
        let url = folder.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - renameItem: folder containing selected file

    func test_renameFolder_updatesSelectedFileToNewPath() throws {
        let folder = try makeSubfolder(named: "OldFolder")
        let fileInFolder = makeFile(in: folder, named: "note.md", content: "content")
        sut.refreshAllFiles()
        sut.openFile(fileInFolder)
        XCTAssertEqual(sut.selectedFile, fileInFolder)

        let newFolderURL = try sut.renameItem(at: folder, to: "NewFolder")
        let expectedNewFile = newFolderURL.appendingPathComponent("note.md")

        XCTAssertEqual(sut.selectedFile, expectedNewFile,
                       "selectedFile should point to the file's new path after folder rename")
    }

    func test_renameFolder_selectedFileContentRemainsAccessible() throws {
        let folder = try makeSubfolder(named: "BeforeRename")
        let fileInFolder = makeFile(in: folder, named: "data.md", content: "important data")
        sut.refreshAllFiles()
        sut.openFile(fileInFolder)

        try sut.renameItem(at: folder, to: "AfterRename")

        XCTAssertEqual(sut.fileContent, "important data",
                       "File content should still be accessible after folder rename")
    }

    func test_renameFolder_notContainingSelectedFile_doesNotChangeSelection() throws {
        let folderA = try makeSubfolder(named: "FolderA")
        let folderB = try makeSubfolder(named: "FolderB")
        let fileInA = makeFile(in: folderA, named: "noteA.md")
        makeFile(in: folderB, named: "noteB.md")
        sut.refreshAllFiles()
        sut.openFile(fileInA)

        try sut.renameItem(at: folderB, to: "FolderB_Renamed")

        XCTAssertEqual(sut.selectedFile, fileInA,
                       "Renaming a folder NOT containing the selected file should leave selection unchanged")
    }

    func test_renameFolder_updatesHistoryEntries() throws {
        let folder = try makeSubfolder(named: "HistoryFolder")
        let file1 = makeFile(in: folder, named: "one.md")
        let file2 = makeFile(in: folder, named: "two.md")
        sut.refreshAllFiles()

        sut.openFile(file1)
        sut.openFile(file2)
        sut.goBack()
        XCTAssertEqual(sut.selectedFile, file1)

        let newFolder = try sut.renameItem(at: folder, to: "RenamedFolder")

        sut.goForward()
        let expectedFile2 = newFolder.appendingPathComponent("two.md")
        XCTAssertEqual(sut.selectedFile, expectedFile2,
                       "Forward navigation should land on the file at its new path")
    }

    // MARK: - deleteItem: folder containing selected file

    func test_deleteFolder_containingSelectedFile_clearsSelection() throws {
        let folder = try makeSubfolder(named: "ToDelete")
        let fileInFolder = makeFile(in: folder, named: "note.md")
        sut.refreshAllFiles()
        sut.openFile(fileInFolder)
        XCTAssertEqual(sut.selectedFile, fileInFolder)

        try sut.deleteItem(at: folder)

        XCTAssertNil(sut.selectedFile,
                     "selectedFile should be nil after its containing folder is deleted")
        XCTAssertEqual(sut.fileContent, "",
                       "fileContent should be cleared after deleting the selected file's folder")
        XCTAssertFalse(sut.isDirty)
    }

    func test_deleteFolder_notContainingSelectedFile_preservesSelection() throws {
        let keepFolder = try makeSubfolder(named: "KeepFolder")
        let deleteFolder = try makeSubfolder(named: "DeleteFolder")
        let keepFile = makeFile(in: keepFolder, named: "keep.md", content: "keep this")
        makeFile(in: deleteFolder, named: "delete.md")
        sut.refreshAllFiles()
        sut.openFile(keepFile)

        try sut.deleteItem(at: deleteFolder)

        XCTAssertEqual(sut.selectedFile, keepFile,
                       "Deleting a folder that does not contain the selected file should preserve selection")
        XCTAssertEqual(sut.fileContent, "keep this")
    }

    func test_deleteFolder_removesChildHistoryEntries() throws {
        let folder = try makeSubfolder(named: "HistToDelete")
        let fileInFolder = makeFile(in: folder, named: "hist.md")
        let outsideFile = makeFile(in: tempDir, named: "outside.md")
        sut.refreshAllFiles()

        sut.openFile(outsideFile)
        sut.openFile(fileInFolder)
        XCTAssertTrue(sut.canGoBack)

        try sut.deleteItem(at: folder)

        XCTAssertFalse(sut.canGoBack,
                       "History entries inside the deleted folder should be purged")
    }

    // MARK: - deleteItem: folder itself is removed from allFiles

    func test_deleteFolder_removesChildFilesFromAllFiles() throws {
        let folder = try makeSubfolder(named: "Folder")
        let file = makeFile(in: folder, named: "child.md")
        sut.refreshAllFiles()
        XCTAssertTrue(sut.allFiles.contains(file))

        try sut.deleteItem(at: folder)

        XCTAssertFalse(sut.allFiles.contains(file),
                       "After deleting a folder, its child files should be removed from allFiles")
    }
}
