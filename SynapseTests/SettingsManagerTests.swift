import XCTest
@testable import Synapse

/// Tests for SettingsManager: config persistence, on-boot command, and file extension filtering
final class SettingsManagerTests: XCTestCase {
    var sut: SettingsManager!
    var tempDir: URL!
    var configFilePath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Use a temp config file for testing
        configFilePath = tempDir.appendingPathComponent("Synapse-settings.json").path
        sut = SettingsManager(configPath: configFilePath)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_defaultValues() {
        XCTAssertEqual(sut.onBootCommand, "", "On-boot command should default to empty")
        XCTAssertEqual(sut.fileExtensionFilter, "*.md, *.txt", "File extension filter should default to *.md, *.txt")
        XCTAssertEqual(sut.hiddenFileFolderFilter, "", "Hidden file/folder filter should default to empty")
        XCTAssertEqual(sut.templatesDirectory, "templates", "Templates directory should default to templates")
    }

    // MARK: - On-Boot Command

    func test_onBootCommand_canBeSet() {
        sut.onBootCommand = "npm run dev"
        XCTAssertEqual(sut.onBootCommand, "npm run dev")
    }

    func test_onBootCommand_canBeCleared() {
        sut.onBootCommand = "npm run dev"
        sut.onBootCommand = ""
        XCTAssertEqual(sut.onBootCommand, "")
    }

    func test_onBootCommand_persistsToDisk() {
        sut.onBootCommand = "claude"

        // Create new instance pointing to same config file
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.onBootCommand, "claude", "On-boot command should persist to disk")
    }

    func test_onBootCommand_emptyMeansNoCommand() {
        sut.onBootCommand = ""
        XCTAssertTrue(sut.onBootCommand.isEmpty, "Empty on-boot command means no command should run")
    }

    // MARK: - File Extension Filter

    func test_fileExtensionFilter_canBeSet() {
        sut.fileExtensionFilter = "*.swift, *.md"
        XCTAssertEqual(sut.fileExtensionFilter, "*.swift, *.md")
    }

    func test_fileExtensionFilter_persistsToDisk() {
        sut.fileExtensionFilter = "*"

        // Create new instance pointing to same config file
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.fileExtensionFilter, "*", "File extension filter should persist to disk")
    }

    func test_fileExtensionFilter_defaultIncludesMdAndTxt() {
        let defaultFilter = sut.fileExtensionFilter
        XCTAssertTrue(defaultFilter.contains("*.md"), "Default filter should include *.md")
        XCTAssertTrue(defaultFilter.contains("*.txt"), "Default filter should include *.txt")
    }

    func test_hiddenFileFolderFilter_persistsToDisk() {
        sut.hiddenFileFolderFilter = "*.project, .private-*"

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.hiddenFileFolderFilter, "*.project, .private-*")
    }

    // MARK: - Templates Directory

    func test_templatesDirectory_canBeSet() {
        sut.templatesDirectory = "snippets"
        XCTAssertEqual(sut.templatesDirectory, "snippets")
    }

    func test_templatesDirectory_persistsToDisk() {
        sut.templatesDirectory = "snippets"

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.templatesDirectory, "snippets")
    }

    // MARK: - Extension Parsing

    func test_parseExtensions_singleExtension() {
        sut.fileExtensionFilter = "*.md"
        let extensions = sut.parsedExtensions
        XCTAssertEqual(extensions, ["md"])
    }

    func test_parseExtensions_multipleExtensions() {
        sut.fileExtensionFilter = "*.md, *.txt, *.swift"
        let extensions = sut.parsedExtensions.sorted()
        XCTAssertEqual(extensions, ["md", "swift", "txt"])
    }

    func test_parseExtensions_withSpaces() {
        sut.fileExtensionFilter = "*.md, *.txt"
        let extensions = sut.parsedExtensions.sorted()
        XCTAssertEqual(extensions, ["md", "txt"])
    }

    func test_parseExtensions_wildcardAllFiles() {
        sut.fileExtensionFilter = "*"
        let extensions = sut.parsedExtensions
        XCTAssertTrue(extensions.isEmpty, "Wildcard * should return empty array (meaning all files)")
    }

    func test_parseExtensions_emptyString() {
        sut.fileExtensionFilter = ""
        let extensions = sut.parsedExtensions
        XCTAssertTrue(extensions.isEmpty, "Empty filter should return empty array (meaning all files)")
    }

    func test_parseHiddenPatterns_multiplePatterns() {
        sut.hiddenFileFolderFilter = "*.project, .git, .private-*"

        XCTAssertEqual(sut.parsedHiddenPatterns, ["*.project", ".git", ".private-*"])
    }

    // MARK: - File Matching

    func test_shouldShowFile_withMatchingExtension() {
        sut.fileExtensionFilter = "*.md, *.txt"
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let txtFile = URL(fileURLWithPath: "/test/note.txt")

        XCTAssertTrue(sut.shouldShowFile(mdFile), "Should show .md files when filter includes *.md")
        XCTAssertTrue(sut.shouldShowFile(txtFile), "Should show .txt files when filter includes *.txt")
    }

    func test_shouldShowFile_withNonMatchingExtension() {
        sut.fileExtensionFilter = "*.md"
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")

        XCTAssertFalse(sut.shouldShowFile(swiftFile), "Should not show .swift files when filter is *.md")
    }

    func test_shouldShowFile_wildcardShowsAll() {
        sut.fileExtensionFilter = "*"
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")
        let mdFile = URL(fileURLWithPath: "/test/note.md")
        let noExtFile = URL(fileURLWithPath: "/test/README")

        XCTAssertTrue(sut.shouldShowFile(swiftFile), "Should show all files with wildcard filter")
        XCTAssertTrue(sut.shouldShowFile(mdFile), "Should show all files with wildcard filter")
        XCTAssertTrue(sut.shouldShowFile(noExtFile), "Should show all files with wildcard filter")
    }

    func test_shouldShowFile_emptyFilterShowsAll() {
        sut.fileExtensionFilter = ""
        let swiftFile = URL(fileURLWithPath: "/test/code.swift")

        XCTAssertTrue(sut.shouldShowFile(swiftFile), "Should show all files when filter is empty")
    }

    func test_shouldShowFile_isCaseInsensitive() {
        sut.fileExtensionFilter = "*.md"
        let upperFile = URL(fileURLWithPath: "/test/note.MD")
        let mixedFile = URL(fileURLWithPath: "/test/note.Md")

        XCTAssertTrue(sut.shouldShowFile(upperFile), "Should be case insensitive")
        XCTAssertTrue(sut.shouldShowFile(mixedFile), "Should be case insensitive")
    }

    func test_shouldHideItem_matchesExactAndWildcardPatterns() {
        sut.hiddenFileFolderFilter = "*.project, .git, .private-*"

        XCTAssertTrue(sut.shouldHideItem(named: "Folder.project"))
        XCTAssertTrue(sut.shouldHideItem(named: ".git"))
        XCTAssertTrue(sut.shouldHideItem(named: ".private-cache"))
        XCTAssertFalse(sut.shouldHideItem(named: "notes"))
    }

    func test_shouldShowFile_returnsFalseWhenParentFolderMatchesHiddenPattern() {
        sut.fileExtensionFilter = "*"
        sut.hiddenFileFolderFilter = ".private-*"

        let root = URL(fileURLWithPath: "/test")
        let hiddenFile = URL(fileURLWithPath: "/test/.private-cache/note.md")

        XCTAssertFalse(sut.shouldShowFile(hiddenFile, relativeTo: root))
    }

    // MARK: - Config Persistence

    func test_save_writesToDisk() {
        sut.onBootCommand = "opencode"
        sut.fileExtensionFilter = "*.md"

        XCTAssertTrue(FileManager.default.fileExists(atPath: configFilePath), "Config file should exist after saving")

        // Read raw JSON
        let data = try! Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["onBootCommand"] as? String, "opencode")
        XCTAssertEqual(json["fileExtensionFilter"] as? String, "*.md")
        XCTAssertEqual(json["templatesDirectory"] as? String, "templates")
    }

    func test_load_readsFromDisk() {
        // Pre-write a config file
        let config: [String: Any] = [
            "onBootCommand": "npm start",
            "fileExtensionFilter": "*.swift",
            "templatesDirectory": "snippets",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        // Create new manager pointing to existing config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "npm start")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.swift")
        XCTAssertEqual(newManager.templatesDirectory, "snippets")
    }

    func test_load_legacyPinnedItemsWithoutIsTag_preservesOtherSettings() {
        let legacyPinnedItem: [String: Any] = [
            "id": UUID().uuidString,
            "url": "file:///tmp/legacy-note.md",
            "name": "legacy-note.md",
            "isFolder": false,
            "vaultPath": "/tmp/vault"
        ]
        let config: [String: Any] = [
            "onBootCommand": "legacy command",
            "fileExtensionFilter": "*.swift",
            "templatesDirectory": "snippets",
            "autoSave": false,
            "autoPush": false,
            "pinnedItems": [legacyPinnedItem]
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "legacy command",
                       "Legacy pinned item decoding should not reset unrelated settings")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.swift")
        XCTAssertEqual(newManager.templatesDirectory, "snippets")
        XCTAssertEqual(newManager.pinnedItems.count, 1)
        XCTAssertFalse(newManager.pinnedItems[0].isTag)
    }

    func test_load_missingTemplatesDirectoryUsesDefaultAndPreservesOtherSettings() {
        let config: [String: Any] = [
            "onBootCommand": "npm start",
            "fileExtensionFilter": "*.swift",
            "autoSave": true,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.templatesDirectory, "templates")
        XCTAssertTrue(newManager.autoSave)
        XCTAssertFalse(newManager.autoPush)
    }

    func test_load_missingFileUsesDefaults() {
        // Delete config file if it exists
        try? FileManager.default.removeItem(atPath: configFilePath)

        // Create new manager without existing config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.md, *.txt")
        XCTAssertEqual(newManager.templatesDirectory, "templates")
    }

    func test_load_invalidJsonUsesDefaults() {
        // Write invalid JSON
        let invalidData = "not valid json".data(using: .utf8)!
        try! invalidData.write(to: URL(fileURLWithPath: configFilePath))

        // Create new manager with invalid config
        let newManager = SettingsManager(configPath: configFilePath)

        XCTAssertEqual(newManager.onBootCommand, "")
        XCTAssertEqual(newManager.fileExtensionFilter, "*.md, *.txt")
        XCTAssertEqual(newManager.templatesDirectory, "templates")
    }

    // MARK: - Changes Notification

    func test_settingOnBootCommand_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.onBootCommand = "new command"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting onBootCommand should trigger save notification")
        cancellable.cancel()
    }

    func test_settingFileExtensionFilter_triggersSave() {
        var saveCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            saveCount += 1
        }

        sut.fileExtensionFilter = "*.swift"

        XCTAssertGreaterThanOrEqual(saveCount, 1, "Setting fileExtensionFilter should trigger save notification")
        cancellable.cancel()
    }

    // MARK: - Sidebar Panes

    func test_initialState_defaultSidebarPanes() {
        XCTAssertEqual(sut.leftSidebarPanes, [.files, .tags, .links])
        XCTAssertEqual(sut.rightSidebarPanes, [.terminal])
    }

    func test_leftSidebarPanes_canBeModified() {
        sut.leftSidebarPanes = [.files]
        XCTAssertEqual(sut.leftSidebarPanes, [.files])
    }

    func test_rightSidebarPanes_canBeModified() {
        sut.rightSidebarPanes = [.links, .tags]
        XCTAssertEqual(sut.rightSidebarPanes, [.links, .tags])
    }

    func test_sidebarPanes_persistToDisk() {
        sut.leftSidebarPanes = [.tags, .files]
        sut.rightSidebarPanes = [.links]

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.leftSidebarPanes, [.tags, .files])
        XCTAssertEqual(newManager.rightSidebarPanes, [.links])
    }

    func test_sidebarPanes_movingPaneFromLeftToRight() {
        // Start: left=[files, tags, links], right=[terminal]
        sut.leftSidebarPanes.removeAll { $0 == .links }
        sut.rightSidebarPanes.append(.links)

        XCTAssertFalse(sut.leftSidebarPanes.contains(.links))
        XCTAssertTrue(sut.rightSidebarPanes.contains(.links))
    }

    func test_sidebarPanes_emptyLeftPanes_persistAndLoad() {
        sut.leftSidebarPanes = []

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.leftSidebarPanes, [])
    }

    func test_load_missingSidebarPanesUsesDefaults() {
        let config: [String: Any] = [
            "onBootCommand": "",
            "fileExtensionFilter": "*.md, *.txt",
            "templatesDirectory": "templates",
            "autoSave": false,
            "autoPush": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        try! data.write(to: URL(fileURLWithPath: configFilePath))

        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.leftSidebarPanes, [.files, .tags, .links])
        XCTAssertEqual(newManager.rightSidebarPanes, [.terminal])
    }

    // MARK: - Default Config Path

    func test_defaultConfigPath_inApplicationSupport() {
        let manager = SettingsManager()
        let expectedPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Synapse/settings.yml")
            .path

        // This is a bit of a hack since we can't easily test the default init without mocking
        // but we can at least verify the default path pattern
        XCTAssertTrue(manager.configPath.contains("Synapse"), "Default config path should be in Application Support/Synapse")
        XCTAssertEqual(manager.configPath, expectedPath)
        XCTAssertTrue(manager.configPath.hasSuffix(".yml"), "Default config should be YAML file")
    }

    // MARK: - Graph Pane

    func test_graphPane_canBeAddedToLeftSidebar() {
        sut.leftSidebarPanes.append(.graph)
        XCTAssertTrue(sut.leftSidebarPanes.contains(.graph))
    }

    func test_graphPane_canBeAddedToRightSidebar() {
        sut.rightSidebarPanes.append(.graph)
        XCTAssertTrue(sut.rightSidebarPanes.contains(.graph))
    }

    func test_graphPane_titleIsGraph() {
        XCTAssertEqual(SidebarPane.graph.title, "Graph")
    }

    func test_graphPane_rawValueIsGraph() {
        XCTAssertEqual(SidebarPane.graph.rawValue, "graph")
    }

    func test_graphPane_persistsToDisk() {
        sut.leftSidebarPanes = [.graph]
        let newManager = SettingsManager(configPath: configFilePath)
        XCTAssertEqual(newManager.leftSidebarPanes, [.graph])
    }

    func test_graphPane_includedInCaseIterable() {
        XCTAssertTrue(SidebarPane.allCases.contains(.graph))
    }

    // MARK: - Vault-Specific Settings (.noted)

    func test_vaultSpecificSettings_usesNotedFolderWhenVaultRootProvided() {
        // Create a mock vault directory
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "TestVault")

        // Initialize SettingsManager with vault root
        let notedSettings = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        // Change a setting
        notedSettings.fileExtensionFilter = "*.swift"

        // Verify the settings file was created in .noted folder
        let notedDir = vaultDir.appendingPathComponent(".noted", isDirectory: true)
        let settingsFile = notedDir.appendingPathComponent("settings.yml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsFile.path),
                      "Settings file should be created in .noted folder")

        // Create new manager pointing to same vault and verify settings persisted
        let newManager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(newManager.fileExtensionFilter, "*.swift",
                       "Settings should persist to .noted/settings.yml")
    }

    func test_vaultSpecificSettings_createsNotedFolderAutomatically() {
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "CreateNoted")

        // .noted folder should not exist initially
        let notedDir = vaultDir.appendingPathComponent(".noted", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: notedDir.path),
                       ".noted folder should not exist initially")

        // Initialize SettingsManager - should create .noted folder
        let _ = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: notedDir.path),
                      ".noted folder should be created automatically")
    }

    func test_vaultSpecificSettings_githubPATStaysInApplicationSupport() {
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)

        // Create a separate Application Support config file for testing
        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let globalConfigPath = appSupportDir.appendingPathComponent("settings.yml").path

        // Initialize manager with both vault root and global config path
        var manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        // Set githubPAT - should go to global config
        manager.githubPAT = "ghp_test_token"

        // Verify token was saved to global config, not vault config
        let notedSettingsFile = vaultDir.appendingPathComponent(".noted/settings.yml")
        let globalText = try! String(contentsOfFile: globalConfigPath, encoding: .utf8)
        XCTAssertTrue(globalText.contains("githubPAT:"))
        XCTAssertTrue(globalText.contains("ghp_test_token"),
                      "githubPAT should be saved to global config")

        // Verify token is NOT in vault config
        let vaultText = try! String(contentsOf: notedSettingsFile, encoding: .utf8)
        XCTAssertFalse(vaultText.contains("githubPAT:"),
                       "githubPAT should NOT be saved to vault-specific config")
    }

    func test_vaultSpecificSettings_layoutSettingsStayInApplicationSupport() {
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)

        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let globalConfigPath = appSupportDir.appendingPathComponent("settings.yml").path

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        manager.leftSidebarPanes = [.files, .links]
        manager.rightSidebarPanes = [.terminal, .tags]
        manager.leftPaneHeights = [:]
        manager.rightPaneHeights = [:]
        manager.collapsedPanes = []
        manager.fileTreeMode = .folder

        let vaultText = try! String(contentsOf: vaultDir.appendingPathComponent(".noted/settings.yml"), encoding: .utf8)
        let globalText = try! String(contentsOfFile: globalConfigPath, encoding: .utf8)

        XCTAssertFalse(vaultText.contains("leftSidebarPanes:"))
        XCTAssertFalse(vaultText.contains("rightSidebarPanes:"))
        XCTAssertFalse(vaultText.contains("leftPaneHeights:"))
        XCTAssertFalse(vaultText.contains("rightPaneHeights:"))
        XCTAssertFalse(vaultText.contains("collapsedPanes:"))
        XCTAssertFalse(vaultText.contains("fileTreeMode:"))

        XCTAssertTrue(globalText.contains("leftSidebarPanes:"))
        XCTAssertTrue(globalText.contains("- files"))
        XCTAssertTrue(globalText.contains("- links"))
        XCTAssertTrue(globalText.contains("rightSidebarPanes:"))
        XCTAssertTrue(globalText.contains("- terminal"))
        XCTAssertTrue(globalText.contains("- tags"))
        XCTAssertTrue(globalText.contains("leftPaneHeights: {}"))
        XCTAssertTrue(globalText.contains("rightPaneHeights: {}"))
        XCTAssertTrue(globalText.contains("collapsedPanes: []"))
        XCTAssertTrue(globalText.contains("fileTreeMode: folder"))
    }

    func test_vaultSpecificSettings_loadsLayoutSettingsFromGlobalConfig() {
        let vaultDir = tempDir.appendingPathComponent("LayoutVault", isDirectory: true)
        let notedDir = vaultDir.appendingPathComponent(".noted", isDirectory: true)
        try! FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)

        let appSupportDir = tempDir.appendingPathComponent("AppSupport", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let globalConfigPath = appSupportDir.appendingPathComponent("settings.yml")

        let vaultYAML = """
        onBootCommand: opencode
        fileExtensionFilter: '*.md'
        templatesDirectory: templates
        autoSave: true
        autoPush: false
        pinnedItems: []
        """
        try! vaultYAML.write(to: notedDir.appendingPathComponent("settings.yml"), atomically: true, encoding: .utf8)

        let globalYAML = """
        githubPAT: ghp_test_token
        leftSidebarPanes:
          - files
          - links
        rightSidebarPanes:
          - terminal
          - tags
        leftPaneHeights: {}
        rightPaneHeights: {}
        collapsedPanes: []
        fileTreeMode: folder
        """
        try! globalYAML.write(to: globalConfigPath, atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath.path)

        XCTAssertEqual(manager.leftSidebarPanes, [.files, .links])
        XCTAssertEqual(manager.rightSidebarPanes, [.terminal, .tags])
        XCTAssertEqual(manager.leftPaneHeights, [:])
        XCTAssertEqual(manager.rightPaneHeights, [:])
        XCTAssertEqual(manager.collapsedPanes, [])
        XCTAssertEqual(manager.fileTreeMode, .folder)
        XCTAssertEqual(manager.githubPAT, "ghp_test_token")
    }

    func test_vaultSpecificSettings_otherSettingsGoToNotedFolder() {
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "OtherSettings")

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        // Set various non-sensitive settings
        manager.onBootCommand = "npm start"
        manager.fileExtensionFilter = "*.md, *.swift"
        manager.hiddenFileFolderFilter = ".git, .build"
        manager.templatesDirectory = "my-templates"
        manager.dailyNotesEnabled = true
        manager.autoSave = true

        // Verify all these settings are in vault config
        let notedSettingsFile = vaultDir.appendingPathComponent(".noted/settings.yml")
        let yaml = try! String(contentsOf: notedSettingsFile, encoding: .utf8)

        XCTAssertTrue(yaml.contains("onBootCommand:"))
        XCTAssertTrue(yaml.contains("npm start"))
        XCTAssertTrue(yaml.contains("fileExtensionFilter:"))
        XCTAssertTrue(yaml.contains("*.md, *.swift"))
        XCTAssertTrue(yaml.contains("hiddenFileFolderFilter:"))
        XCTAssertTrue(yaml.contains(".git, .build"))
        XCTAssertTrue(yaml.contains("templatesDirectory: my-templates"))
        XCTAssertTrue(yaml.contains("dailyNotesEnabled: true"))
        XCTAssertTrue(yaml.contains("autoSave: true"))
    }

    func test_vaultSpecificSettings_withoutVaultRootUsesDefaults() {
        // Initialize without vault root - should use defaults
        let manager = SettingsManager(vaultRoot: nil)

        // All settings should have default values
        XCTAssertEqual(manager.onBootCommand, "")
        XCTAssertEqual(manager.fileExtensionFilter, "*.md, *.txt")
        XCTAssertEqual(manager.hiddenFileFolderFilter, "")
        XCTAssertEqual(manager.templatesDirectory, "templates")
        XCTAssertEqual(manager.githubPAT, "")
    }

    func test_vaultSpecificSettings_changingVaultReloadsSettings() {
        // Create two vaults with different settings
        let vault1 = tempDir.appendingPathComponent("Vault1", isDirectory: true)
        let vault2 = tempDir.appendingPathComponent("Vault2", isDirectory: true)
        try! FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "VaultSwitch")

        // Set up different settings in each vault
        let manager1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfigPath)
        manager1.fileExtensionFilter = "*.md"
        manager1.onBootCommand = "vault1-cmd"

        let manager2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfigPath)
        manager2.fileExtensionFilter = "*.swift"
        manager2.onBootCommand = "vault2-cmd"

        // Create new manager for vault1 and verify it loads vault1's settings
        let newManager1 = SettingsManager(vaultRoot: vault1, globalConfigPath: globalConfigPath)
        XCTAssertEqual(newManager1.fileExtensionFilter, "*.md")
        XCTAssertEqual(newManager1.onBootCommand, "vault1-cmd")

        // Create new manager for vault2 and verify it loads vault2's settings
        let newManager2 = SettingsManager(vaultRoot: vault2, globalConfigPath: globalConfigPath)
        XCTAssertEqual(newManager2.fileExtensionFilter, "*.swift")
        XCTAssertEqual(newManager2.onBootCommand, "vault2-cmd")
    }

    func test_vaultSpecificSettings_loadsExistingYAMLFile() {
        let vaultDir = tempDir.appendingPathComponent("VaultYAML", isDirectory: true)
        let notedDir = vaultDir.appendingPathComponent(".noted", isDirectory: true)
        try! FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "VaultYAML")

        let yaml = """
        onBootCommand: opencode
        fileExtensionFilter: '*.md, *.swift'
        hiddenFileFolderFilter: .git
        templatesDirectory: templates
        dailyNotesEnabled: true
        dailyNotesFolder: daily
        dailyNotesTemplate: Daily Note.md
        dailyNotesOpenOnStartup: true
        autoSave: true
        autoPush: false
        leftSidebarPanes:
          - files
          - tags
        rightSidebarPanes:
          - terminal
        leftPaneHeights: {}
        rightPaneHeights: {}
        collapsedPanes: []
        fileTreeMode: folder
        pinnedItems: []
        """
        try! yaml.write(to: notedDir.appendingPathComponent("settings.yml"), atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        XCTAssertEqual(manager.onBootCommand, "opencode")
        XCTAssertEqual(manager.fileExtensionFilter, "*.md, *.swift")
        XCTAssertEqual(manager.hiddenFileFolderFilter, ".git")
        XCTAssertTrue(manager.dailyNotesEnabled)
        XCTAssertTrue(manager.autoSave)
        XCTAssertEqual(manager.leftSidebarPanes, [.files, .tags, .links])
        XCTAssertEqual(manager.rightSidebarPanes, [.terminal])
    }

    private func makeGlobalConfigPath(named name: String) -> String {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport-\(name)", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        return appSupportDir.appendingPathComponent("settings.yml").path
    }
}
