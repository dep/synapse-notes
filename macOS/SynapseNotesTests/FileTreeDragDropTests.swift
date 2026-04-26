import XCTest
@testable import Synapse

/// Tests for file drag-and-drop within the file tree (Issue #180).
///
/// Covers:
/// - moveFile(at:toFolder:) happy path (different folder)
/// - moveFile to root
/// - no-op when dropped onto current parent folder
/// - conflict: destination has a file with same name (throws itemAlreadyExists)
/// - moveFile with overwrite: true replaces existing file
/// - moving a file updates the selected-file pointer
/// - moving a non-existent source throws operationFailed
/// - moving when no workspace is set throws noWorkspace
final class FileTreeDragDropTests: XCTestCase {

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

    private func makeFile(named name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? tempDir!
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "content".data(using: .utf8))
        return url
    }

    private func makeFolder(named name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? tempDir!
        let url = dir.appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - moveFile: happy path to a different folder

    func test_moveFile_toNewFolder_movesFileOnDisk() throws {
        let src = makeFile(named: "note.md")
        let destFolder = makeFolder(named: "folder-a")

        let result = try sut.moveFile(at: src, toFolder: destFolder)

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path),
                       "Source file should no longer exist at its original location")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path),
                      "File should exist at new destination")
        XCTAssertEqual(result.deletingLastPathComponent().standardizedFileURL,
                       destFolder.standardizedFileURL,
                       "Destination parent should be the target folder")
        XCTAssertEqual(result.lastPathComponent, "note.md")
    }

    func test_moveFile_toNewFolder_preservesFileName() throws {
        let src = makeFile(named: "my-note.md")
        let destFolder = makeFolder(named: "folder-b")

        let result = try sut.moveFile(at: src, toFolder: destFolder)

        XCTAssertEqual(result.lastPathComponent, "my-note.md")
    }

    // MARK: - moveFile: move to root

    func test_moveFile_toRootFolder_movesFileToRoot() throws {
        let subfolder = makeFolder(named: "sub")
        let src = makeFile(named: "root-move.md", in: subfolder)
        let root = tempDir!

        let result = try sut.moveFile(at: src, toFolder: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertEqual(result.deletingLastPathComponent().standardizedFileURL,
                       root.standardizedFileURL)
    }

    // MARK: - moveFile: no-op when same parent folder

    func test_moveFile_toSameFolder_isNoOp() throws {
        let src = makeFile(named: "stay.md")
        let sameFolder = tempDir!

        let result = try sut.moveFile(at: src, toFolder: sameFolder)

        // File should remain at the same location; result should equal source
        XCTAssertEqual(result.standardizedFileURL, src.standardizedFileURL,
                       "Moving a file to its current parent should be a no-op")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }

    // MARK: - moveFile: conflict without overwrite throws

    func test_moveFile_conflictingName_throwsItemAlreadyExists() throws {
        let src = makeFile(named: "conflict.md")
        let destFolder = makeFolder(named: "dest")
        // Pre-create a file with the same name in the destination
        _ = makeFile(named: "conflict.md", in: destFolder)

        XCTAssertThrowsError(try sut.moveFile(at: src, toFolder: destFolder)) { error in
            if case .itemAlreadyExists = error as? FileBrowserError { return }
            XCTFail("Expected .itemAlreadyExists, got \(error)")
        }
    }

    // MARK: - moveFile: conflict with overwrite:true replaces file

    func test_moveFile_conflictWithOverwrite_replacesDestinationFile() throws {
        let src = makeFile(named: "overwrite-me.md")
        let destFolder = makeFolder(named: "over-dest")
        let existingDest = makeFile(named: "overwrite-me.md", in: destFolder)

        // Write distinct content so we can tell which file won
        try "new-content".write(to: src, atomically: true, encoding: .utf8)
        try "old-content".write(to: existingDest, atomically: true, encoding: .utf8)

        let result = try sut.moveFile(at: src, toFolder: destFolder, overwrite: true)

        let content = try String(contentsOf: result, encoding: .utf8)
        XCTAssertEqual(content, "new-content", "Overwrite should replace the destination with the source content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))

        let stagingLeftovers = try FileManager.default.contentsOfDirectory(atPath: destFolder.path)
            .filter { $0.hasPrefix(".synapse-move-") }
        XCTAssertTrue(stagingLeftovers.isEmpty, "Overwrite should not leave staging files in the destination folder")
    }

    // MARK: - moveFile: updates selectedFile

    func test_moveFile_updatesSelectedFilePointerWhenMovingOpenFile() throws {
        let src = makeFile(named: "open-note.md")
        sut.openFile(src)
        XCTAssertEqual(sut.selectedFile?.standardizedFileURL, src.standardizedFileURL)

        let destFolder = makeFolder(named: "target")
        let result = try sut.moveFile(at: src, toFolder: destFolder)

        XCTAssertEqual(sut.selectedFile?.standardizedFileURL, result.standardizedFileURL,
                       "selectedFile should update to the new location after move")
    }

    // MARK: - moveFile: updates allFiles

    func test_moveFile_updatesAllFilesAfterMove() throws {
        let src = makeFile(named: "tracked.md")
        let destFolder = makeFolder(named: "new-home")

        let result = try sut.moveFile(at: src, toFolder: destFolder)

        XCTAssertFalse(sut.allFiles.contains(src), "Old URL should be removed from allFiles")
        XCTAssertTrue(sut.allFiles.contains(result), "New URL should appear in allFiles")
    }

    // MARK: - moveFile: non-existent source throws

    func test_moveFile_nonExistentSource_throwsOperationFailed() {
        let ghost = tempDir.appendingPathComponent("ghost.md")
        let destFolder = makeFolder(named: "nowhere")

        XCTAssertThrowsError(try sut.moveFile(at: ghost, toFolder: destFolder)) { error in
            if case .operationFailed = error as? FileBrowserError { return }
            XCTFail("Expected .operationFailed, got \(error)")
        }
    }

    // MARK: - moveFile: no workspace throws

    func test_moveFile_noWorkspace_throwsNoWorkspace() {
        sut.rootURL = nil
        let ghost = tempDir.appendingPathComponent("x.md")
        XCTAssertThrowsError(try sut.moveFile(at: ghost, toFolder: tempDir)) { error in
            XCTAssertEqual(error as? FileBrowserError, .noWorkspace)
        }
    }
}
