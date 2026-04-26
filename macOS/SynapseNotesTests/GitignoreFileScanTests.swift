import XCTest
import Combine
@testable import Synapse

/// Tests for Issue #143: .gitignore support in file scanning.
/// Verifies that directories matching .gitignore patterns are skipped,
/// the respectGitignore setting controls this behaviour, and non-git
/// vaults degrade gracefully.
final class GitignoreFileScanTests: XCTestCase {

    var tempDir: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func makeFile(at relativePath: String, content: String = "x") -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func initGitRepo() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = tempDir
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private func writeGitignore(_ contents: String) {
        let url = tempDir.appendingPathComponent(".gitignore")
        try! contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Sets up an AppState with the given settings and waits for the initial scan to settle.
    /// `trigger` is called after subscribing so we never miss the first emission.
    private func makeAppStateAndWaitForScan(
        settings: SettingsManager,
        trigger: (AppState) -> Void
    ) -> AppState {
        let appState = AppState(settings: settings)
        let exp = XCTestExpectation(description: "initial scan completes")
        // Subscribe before triggering the scan.
        appState.$allProjectFiles
            .dropFirst()
            .first { _ in true }
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        trigger(appState)
        wait(for: [exp], timeout: 5.0)
        return appState
    }

    // MARK: - respectGitignore setting defaults to true

    func test_respectGitignore_defaultsToTrue() {
        let settings = SettingsManager(
            vaultRoot: tempDir,
            globalConfigPath: tempDir.appendingPathComponent("global.yml").path
        )
        XCTAssertTrue(settings.respectGitignore,
                      "respectGitignore should default to true")
    }

    // MARK: - respectGitignore persists to disk (vault config)

    func test_respectGitignore_persistsToDisk() {
        let configDir = tempDir.appendingPathComponent(".synapse")
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let globalPath = tempDir.appendingPathComponent("global.yml").path

        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = false

        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        XCTAssertFalse(reloaded.respectGitignore,
                       "respectGitignore = false should survive a save/reload cycle")
    }

    // MARK: - gitignored directories are excluded when respectGitignore is true

    func test_gitignore_excludesNodeModules_whenRespectGitignoreIsTrue() {
        initGitRepo()
        writeGitignore("node_modules/\n")

        // A regular tracked file
        makeFile(at: "notes/note.md")
        // A file inside node_modules (should be ignored)
        makeFile(at: "node_modules/some-package/index.js")

        let globalPath = tempDir.appendingPathComponent("global.yml").path
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = true
        settings.fileExtensionFilter = "*"
        settings.hiddenFileFolderFilter = ""

        let appState = makeAppStateAndWaitForScan(settings: settings) { $0.openFolder(self.tempDir) }

        let paths = appState.allProjectFiles.map { $0.path }
        XCTAssertFalse(paths.contains(where: { $0.contains("node_modules") }),
                       "node_modules contents should not appear in allProjectFiles when respected")
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("note.md") }),
                      "Tracked files should still appear")
    }

    // MARK: - gitignored directories ARE included when respectGitignore is false

    func test_gitignore_includesNodeModules_whenRespectGitignoreIsFalse() {
        initGitRepo()
        writeGitignore("node_modules/\n")

        makeFile(at: "notes/note.md")
        makeFile(at: "node_modules/some-package/index.js")

        let globalPath = tempDir.appendingPathComponent("global.yml").path
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = false
        settings.fileExtensionFilter = "*"
        settings.hiddenFileFolderFilter = ""

        let appState = makeAppStateAndWaitForScan(settings: settings) { $0.openFolder(self.tempDir) }

        let paths = appState.allProjectFiles.map { $0.path }
        XCTAssertTrue(paths.contains(where: { $0.contains("node_modules") }),
                      "node_modules should appear when respectGitignore is false")
    }

    // MARK: - Non-git vault does not error and scans normally

    func test_nonGitVault_scanWorksNormally_withRespectGitignoreEnabled() {
        // No git init, no .gitignore
        makeFile(at: "plain-note.md")
        makeFile(at: "subfolder/another.md")

        let globalPath = tempDir.appendingPathComponent("global.yml").path
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = true  // enabled, but no .git folder
        settings.fileExtensionFilter = "*"
        settings.hiddenFileFolderFilter = ""

        let appState = makeAppStateAndWaitForScan(settings: settings) { $0.openFolder(self.tempDir) }

        XCTAssertFalse(appState.allProjectFiles.isEmpty,
                       "Non-git vault should still discover files with respectGitignore enabled")
        let names = Set(appState.allProjectFiles.map { $0.lastPathComponent })
        XCTAssertTrue(names.contains("plain-note.md"))
        XCTAssertTrue(names.contains("another.md"))
    }

    // MARK: - Existing hidden folder patterns still work alongside gitignore

    func test_hiddenFolderPatterns_workAlongsideGitignore() {
        initGitRepo()
        writeGitignore("node_modules/\n")

        makeFile(at: "notes/note.md")
        makeFile(at: "node_modules/pkg/index.js")
        makeFile(at: ".images/photo.png")  // hidden by user pattern

        let globalPath = tempDir.appendingPathComponent("global.yml").path
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = true
        settings.fileExtensionFilter = "*"
        settings.hiddenFileFolderFilter = ".images"

        let appState = makeAppStateAndWaitForScan(settings: settings) { $0.openFolder(self.tempDir) }

        let paths = appState.allProjectFiles.map { $0.path }
        XCTAssertFalse(paths.contains(where: { $0.contains("node_modules") }),
                       "gitignored node_modules should be excluded")
        XCTAssertFalse(paths.contains(where: { $0.contains(".images") }),
                       "user-hidden .images should also be excluded")
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("note.md") }),
                      "Tracked notes should still appear")
    }

    // MARK: - .git directory is always excluded (gitignore implicit)

    func test_dotGitDirectory_isNeverScanned() {
        initGitRepo()
        makeFile(at: "readme.md")

        let globalPath = tempDir.appendingPathComponent("global.yml").path
        let settings = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        settings.respectGitignore = true
        settings.fileExtensionFilter = "*"
        settings.hiddenFileFolderFilter = ""

        let appState = makeAppStateAndWaitForScan(settings: settings) { $0.openFolder(self.tempDir) }

        let paths = appState.allProjectFiles.map { $0.path }
        XCTAssertFalse(paths.contains(where: { $0.contains("/.git/") }),
                       ".git directory contents should never appear in file lists")
    }
}
