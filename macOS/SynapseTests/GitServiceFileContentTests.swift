import XCTest
@testable import Synapse

/// Tests for `GitService.getFileContent(at:for:)` — the method that retrieves the raw
/// content of a file at a specific git commit SHA.  This powers the file-history viewer
/// feature (the user picks a past commit and sees how the note looked at that point in
/// time).  It was previously untested despite being the only way to surface historical
/// note content.
final class GitServiceFileContentTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard GitService.findGit() != nil else { return }
        initRepo()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Repo helpers

    @discardableResult
    private func git(_ args: [String]) -> String {
        guard let gitPath = GitService.findGit() else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        p.currentDirectoryURL = tempDir
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func initRepo() {
        git(["init"])
        git(["config", "user.email", "test@example.com"])
        git(["config", "user.name", "Test"])
        git(["config", "commit.gpgsign", "false"])
    }

    /// Commits a file with the given content and returns the commit SHA.
    @discardableResult
    private func commit(file: URL, content: String, message: String) -> String {
        try! content.write(to: file, atomically: true, encoding: .utf8)
        // Use the path relative to the repo root so nested files work correctly.
        let relativePath = file.path
            .replacingOccurrences(of: tempDir.path + "/", with: "")
        git(["add", relativePath])
        git(["commit", "-m", message])
        return git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeService() throws -> GitService {
        guard GitService.findGit() != nil else {
            throw XCTSkip("git not available on this system")
        }
        do {
            return try GitService(repoURL: tempDir)
        } catch GitError.gitNotFound {
            throw XCTSkip("git not available on this system")
        } catch GitError.notARepo {
            throw XCTSkip("git repo was not initialised")
        }
    }

    // MARK: - getFileContent(at:for:)

    func test_getFileContent_returnsCorrectContentForFirstCommit() throws {
        let noteFile = tempDir.appendingPathComponent("note.md")
        let sha1 = commit(file: noteFile, content: "# Version 1", message: "v1")

        let service = try makeService()
        let content = service.getFileContent(at: sha1, for: noteFile)

        XCTAssertEqual(content, "# Version 1", "Content at first commit SHA should match what was written")
    }

    func test_getFileContent_returnsContentAtSpecificCommit_notHead() throws {
        let noteFile = tempDir.appendingPathComponent("note.md")
        let sha1 = commit(file: noteFile, content: "# Version 1", message: "v1")
        commit(file: noteFile, content: "# Version 2", message: "v2")

        let service = try makeService()
        let contentAtV1 = service.getFileContent(at: sha1, for: noteFile)

        XCTAssertEqual(contentAtV1, "# Version 1",
                       "Should return the content as it was at sha1, not at HEAD")
    }

    func test_getFileContent_returnsLatestContentAtHeadCommit() throws {
        let noteFile = tempDir.appendingPathComponent("note.md")
        commit(file: noteFile, content: "# Version 1", message: "v1")
        let sha2 = commit(file: noteFile, content: "# Version 2", message: "v2")

        let service = try makeService()
        let contentAtV2 = service.getFileContent(at: sha2, for: noteFile)

        XCTAssertEqual(contentAtV2, "# Version 2",
                       "Should return the content as it was at sha2")
    }

    func test_getFileContent_returnsNilForInvalidSha() throws {
        let noteFile = tempDir.appendingPathComponent("note.md")
        commit(file: noteFile, content: "# Anything", message: "commit")

        let service = try makeService()
        let content = service.getFileContent(at: "0000000000000000000000000000000000000000", for: noteFile)

        XCTAssertNil(content, "An invalid SHA should return nil instead of throwing")
    }

    func test_getFileContent_returnsNilForFileNotPresentAtCommit() throws {
        // Commit file A, then add file B in a second commit.
        // At the first commit's SHA, file B does not exist.
        let fileA = tempDir.appendingPathComponent("a.md")
        let sha1 = commit(file: fileA, content: "A content", message: "add A")
        let fileB = tempDir.appendingPathComponent("b.md")
        commit(file: fileB, content: "B content", message: "add B")

        let service = try makeService()
        let content = service.getFileContent(at: sha1, for: fileB)

        XCTAssertNil(content, "File that didn't exist at sha1 should return nil")
    }

    func test_getFileContent_preservesMultilineContent() throws {
        let multiline = "# Title\n\nParagraph one.\n\nParagraph two.\n"
        let noteFile = tempDir.appendingPathComponent("multi.md")
        let sha = commit(file: noteFile, content: multiline, message: "add multiline")

        let service = try makeService()
        let content = service.getFileContent(at: sha, for: noteFile)

        XCTAssertEqual(content, multiline, "Multi-line content should be preserved exactly")
    }

    func test_getFileContent_worksForNestedFilePath() throws {
        let subdir = tempDir.appendingPathComponent("notes", isDirectory: true)
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let nestedFile = subdir.appendingPathComponent("nested.md")
        let sha = commit(file: nestedFile, content: "Nested content", message: "add nested")

        let service = try makeService()
        let content = service.getFileContent(at: sha, for: nestedFile)

        XCTAssertEqual(content, "Nested content",
                       "getFileContent should work for files in subdirectories")
    }
}
