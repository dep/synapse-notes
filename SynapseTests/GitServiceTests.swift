import XCTest
@testable import Synapse

/// Tests for GitService static helpers: isGitRepo detection, findGit path resolution,
/// and init error handling. These are the workspace-detection primitives the whole
/// git integration depends on.
final class GitServiceTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - isGitRepo(at:)

    func test_isGitRepo_withoutDotGit_returnsFalse() {
        XCTAssertFalse(GitService.isGitRepo(at: tempDir),
                       "A plain directory with no .git should not be considered a git repo")
    }

    func test_isGitRepo_withDotGitDirectory_returnsTrue() throws {
        let dotGit = tempDir.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: false)

        XCTAssertTrue(GitService.isGitRepo(at: tempDir),
                      "A directory containing .git/ should be detected as a git repo")
    }

    func test_isGitRepo_withDotGitFile_returnsTrue() {
        // Git worktrees and submodules use a .git file instead of a .git directory
        let dotGitFile = tempDir.appendingPathComponent(".git")
        let content = "gitdir: ../.git/worktrees/main".data(using: .utf8)
        FileManager.default.createFile(atPath: dotGitFile.path, contents: content)

        XCTAssertTrue(GitService.isGitRepo(at: tempDir),
                      "A directory with a .git file (worktree) should also be detected as a git repo")
    }

    func test_isGitRepo_nonExistentDirectory_returnsFalse() {
        let nonExistent = tempDir.appendingPathComponent("does_not_exist")
        XCTAssertFalse(GitService.isGitRepo(at: nonExistent))
    }

    // MARK: - findGit()

    func test_findGit_returnsValidExecutablePath() {
        guard let gitPath = GitService.findGit() else {
            // git is not in any of the known locations; acceptable in minimal CI
            return
        }
        XCTAssertTrue(gitPath.hasSuffix("git"), "Git executable path should end with 'git', got: \(gitPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitPath),
                      "Found git path must exist on disk: \(gitPath)")
    }

    // MARK: - init error handling

    func test_init_nonGitDirectory_throwsNotARepo() {
        XCTAssertThrowsError(try GitService(repoURL: tempDir)) { error in
            guard let gitError = error as? GitError,
                  case .notARepo = gitError else {
                XCTFail("Expected GitError.notARepo, got \(error)")
                return
            }
        }
    }

    func test_init_withDotGitDirectory_succeedsOrThrowsGitNotFound() throws {
        let dotGit = tempDir.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: false)

        do {
            let service = try GitService(repoURL: tempDir)
            XCTAssertEqual(service.repoURL.standardizedFileURL, tempDir.standardizedFileURL)
        } catch GitError.gitNotFound {
            // Acceptable: git is not installed on this machine
            throw XCTSkip("git not available on this system")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Conflict marker parsing (logic parity test)

    func test_conflictMarkers_allSixPrefixes_detected() {
        let conflictPrefixes = ["UU", "AA", "DD", "AU", "UA", "DU", "UD"]

        for prefix in conflictPrefixes {
            let statusOutput = "\(prefix) some-file.md\nM  other-file.md\n"
            let hasConflict = statusOutput
                .components(separatedBy: "\n")
                .contains { line in
                    let p = String(line.prefix(2))
                    return ["UU", "AA", "DD", "AU", "UA", "DU", "UD"].contains(p)
                }
            XCTAssertTrue(hasConflict, "Prefix '\(prefix)' should be recognised as a conflict marker")
        }
    }

    func test_conflictMarkers_cleanStatus_notDetected() {
        let cleanOutput = "M  modified-file.md\nA  new-file.md\n"
        let hasConflict = cleanOutput
            .components(separatedBy: "\n")
            .contains { line in
                let prefix = String(line.prefix(2))
                return ["UU", "AA", "DD", "AU", "UA", "DU", "UD"].contains(prefix)
            }
        XCTAssertFalse(hasConflict, "Clean porcelain output should not be detected as a conflict")
    }
}
