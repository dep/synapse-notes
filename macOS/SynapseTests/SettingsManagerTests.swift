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

    // MARK: - Fixed Sidebar Layout

    func test_fixedSidebars_alwaysHaveThree() {
        XCTAssertEqual(sut.sidebars.count, 3)
    }

    func test_fixedSidebars_leftSidebarHasFilesAndLinks() {
        let left = sut.leftSidebars
        XCTAssertEqual(left.count, 1)
        XCTAssertTrue(left[0].panes.contains(.files))
        XCTAssertTrue(left[0].panes.contains(.links))
    }

    func test_fixedSidebars_right1HasTerminalAndTags() {
        let right = sut.rightSidebars
        XCTAssertGreaterThanOrEqual(right.count, 1)
        let r1 = right[0]
        XCTAssertTrue(r1.panes.contains(.terminal))
        XCTAssertTrue(r1.panes.contains(.tags))
    }

    func test_fixedSidebars_right2CollapsedByDefault() {
        XCTAssertTrue(sut.collapsedSidebarIDs.contains(FixedSidebar.right2ID.uuidString))
    }

    func test_removePane_removesPaneFromSidebar() {
        sut.removePane(.links, fromSidebar: FixedSidebar.leftID)
        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }
        // Left sidebar now has [calendar, files, links] by default
        // After removing links, should be [calendar, files]
        XCTAssertEqual(left?.panes, [.builtIn(.calendar), .builtIn(.files)])
    }

    func test_assignPane_movesPaneToAnotherSidebar() {
        sut.assignPane(.links, toSidebar: FixedSidebar.right1ID)
        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }
        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }
        XCTAssertFalse(left?.panes.contains(.links) ?? true)
        XCTAssertTrue(right1?.panes.contains(.links) ?? false)
    }

    func test_movePane_reordersWithinSameSidebar() {
        sut.movePane(.tags, toSidebar: FixedSidebar.right1ID, at: 0)
        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }
        XCTAssertEqual(right1?.panes, [.builtIn(.tags), .builtIn(.terminal)])
    }

    func test_movePaneItem_notePane_reordersWithinSameSidebar() {
        let noteA = SidebarPaneItem.file(fileURL: tempDir.appendingPathComponent("A.md"))
        let noteB = SidebarPaneItem.file(fileURL: tempDir.appendingPathComponent("B.md"))

        sut.sidebars = [
            Sidebar(id: FixedSidebar.leftID, position: .left, panes: [.builtIn(.files), noteA, noteB]),
            Sidebar(id: FixedSidebar.right1ID, position: .right, panes: [.builtIn(.terminal), .builtIn(.tags)]),
            Sidebar(id: FixedSidebar.right2ID, position: .right, panes: [.builtIn(.browser)]),
        ]

        sut.movePaneItem(noteB, toSidebar: FixedSidebar.leftID, at: 1)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }
        XCTAssertEqual(left?.panes, [.builtIn(.files), noteB, noteA])
    }

    func test_movePaneItem_notePane_movesAcrossSidebars() {
        let note = SidebarPaneItem.file(fileURL: tempDir.appendingPathComponent("Reference.md"))

        sut.sidebars = [
            Sidebar(id: FixedSidebar.leftID, position: .left, panes: [.builtIn(.files), note]),
            Sidebar(id: FixedSidebar.right1ID, position: .right, panes: [.builtIn(.terminal), .builtIn(.tags)]),
            Sidebar(id: FixedSidebar.right2ID, position: .right, panes: [.builtIn(.browser)]),
        ]

        sut.movePaneItem(note, toSidebar: FixedSidebar.right1ID, at: 1)

        let left = sut.sidebars.first { $0.id == FixedSidebar.leftID }
        let right1 = sut.sidebars.first { $0.id == FixedSidebar.right1ID }

        XCTAssertEqual(left?.panes, [.builtIn(.files)])
        XCTAssertEqual(right1?.panes, [.builtIn(.terminal), note, .builtIn(.tags)])
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

    func test_graphPane_titleIsGraph() {
        XCTAssertEqual(SidebarPane.graph.title, "Graph")
    }

    func test_graphPane_rawValueIsGraph() {
        XCTAssertEqual(SidebarPane.graph.rawValue, "graph")
    }

    func test_graphPane_includedInCaseIterable() {
        XCTAssertTrue(SidebarPane.allCases.contains(.graph))
    }

    func test_right2Sidebar_startsWithBrowser() {
        let right2 = sut.sidebars.first { $0.id == FixedSidebar.right2ID }
        XCTAssertNotNil(right2)
        XCTAssertEqual(right2!.panes, [.builtIn(.browser)])
    }

    func test_graphPane_startsAvailable() {
        XCTAssertTrue(sut.availablePanes.contains(.graph))
    }

    // MARK: - Vault-Specific Settings (.synapse)

    func test_vaultSpecificSettings_usesNotedFolderWhenVaultRootProvided() {
        // Create a mock vault directory
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "TestVault")

        // Initialize SettingsManager with vault root
        let notedSettings = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        // Change a setting
        notedSettings.fileExtensionFilter = "*.swift"

        // Verify the settings file was created in .synapse folder
        let notedDir = vaultDir.appendingPathComponent(".synapse", isDirectory: true)
        let settingsFile = notedDir.appendingPathComponent("settings.yml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsFile.path),
                      "Settings file should be created in .synapse folder")

        // Create new manager pointing to same vault and verify settings persisted
        let newManager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)
        XCTAssertEqual(newManager.fileExtensionFilter, "*.swift",
                       "Settings should persist to .synapse/settings.yml")
    }

    func test_vaultSpecificSettings_createsNotedFolderAutomatically() {
        let vaultDir = tempDir.appendingPathComponent("TestVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "CreateNoted")

        // .synapse folder should not exist initially
        let notedDir = vaultDir.appendingPathComponent(".synapse", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: notedDir.path),
                       ".synapse folder should not exist initially")

        // Initialize SettingsManager - should create .synapse folder
        let _ = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: notedDir.path),
                      ".synapse folder should be created automatically")
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
        let notedSettingsFile = vaultDir.appendingPathComponent(".synapse/settings.yml")
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
        manager.sidebarPaneHeights = ["files": 400]
        manager.collapsedPanes = []
        manager.fileTreeMode = .folder

        let vaultText = try! String(contentsOf: vaultDir.appendingPathComponent(".synapse/settings.yml"), encoding: .utf8)
        let globalText = try! String(contentsOfFile: globalConfigPath, encoding: .utf8)

        // Vault file should NOT contain layout settings
        XCTAssertFalse(vaultText.contains("sidebarPaneHeights:"))
        XCTAssertFalse(vaultText.contains("collapsedPanes:"))
        XCTAssertFalse(vaultText.contains("fileTreeMode:"))

        // Global config should contain layout settings
        XCTAssertTrue(globalText.contains("fileTreeMode: folder"))
    }

    func test_vaultSpecificSettings_loadsLayoutSettingsFromGlobalConfig() {
        let vaultDir = tempDir.appendingPathComponent("LayoutVault", isDirectory: true)
        let notedDir = vaultDir.appendingPathComponent(".synapse", isDirectory: true)
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
        collapsedPanes: []
        fileTreeMode: folder
        """
        try! globalYAML.write(to: globalConfigPath, atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath.path)

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
        let notedSettingsFile = vaultDir.appendingPathComponent(".synapse/settings.yml")
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
        let notedDir = vaultDir.appendingPathComponent(".synapse", isDirectory: true)
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
        launchBehavior: dailyNote
        launchSpecificNotePath: notes/startup.md
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
        XCTAssertEqual(manager.launchBehavior, .dailyNote)
        XCTAssertEqual(manager.launchSpecificNotePath, "notes/startup.md")
        XCTAssertTrue(manager.autoSave)
        // Fixed sidebars always have 3 entries
        XCTAssertEqual(manager.sidebars.count, 3)
    }

    func test_vaultSpecificSettings_loadsPinnedItemsWithVaultPathsArray() {
        let vaultDir = tempDir.appendingPathComponent("VaultYAMLWithPins", isDirectory: true)
        let notedDir = vaultDir.appendingPathComponent(".synapse", isDirectory: true)
        try! FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)
        let globalConfigPath = makeGlobalConfigPath(named: "VaultYAMLWithPins")

        let noteURL = vaultDir.appendingPathComponent("Pages/Weight Log.md")
        try! FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! "".write(to: noteURL, atomically: true, encoding: .utf8)

        let otherVault = tempDir.appendingPathComponent("OtherVault", isDirectory: true)
        try! FileManager.default.createDirectory(at: otherVault, withIntermediateDirectories: true)

        let yaml = """
        onBootCommand: ''
        fileExtensionFilter: '*.md, *.txt, *.yml, *.json'
        templatesDirectory: .templates
        dailyNotesEnabled: true
        autoSave: true
        autoPush: true
        pinnedItems:
        - id: 159CE250-1812-480B-8695-6937583EDF42
          name: Weight Log.md
          isFolder: false
          isTag: false
          vaultPaths:
            - \(otherVault.path)
            - \(vaultDir.path)
          relativePath: Pages/Weight Log.md
        defaultEditMode: true
        hideMarkdownWhileEditing: true
        browserStartupURL: tasks.google.com
        """
        try! yaml.write(to: notedDir.appendingPathComponent("settings.yml"), atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath)

        XCTAssertEqual(manager.fileExtensionFilter, "*.md, *.txt, *.yml, *.json")
        XCTAssertEqual(manager.templatesDirectory, ".templates")
        XCTAssertTrue(manager.dailyNotesEnabled)
        XCTAssertTrue(manager.autoSave)
        XCTAssertTrue(manager.autoPush)
        XCTAssertEqual(manager.pinnedItems.count, 1)
        XCTAssertEqual(manager.pinnedItems[0].url?.path, noteURL.path)
    }

    // MARK: - Vault Paths Discovery

    func test_vaultPaths_loadsFromGlobalConfig() {
        // Create global config with vaultPaths array
        let globalYAML = """
        githubPAT: secret-token
        vaultPaths:
          - /Users/alice/Documents/Vaults
          - /home/alice/obsidian-vaults
          - "C:\\\\Users\\\\alice\\\\Documents\\\\Vaults"
        """
        let globalConfigPath = makeGlobalConfigPath(named: "vaultpaths-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)

        XCTAssertEqual(manager.vaultPaths.count, 3)
        XCTAssertEqual(manager.vaultPaths[0], "/Users/alice/Documents/Vaults")
        XCTAssertEqual(manager.vaultPaths[1], "/home/alice/obsidian-vaults")
        XCTAssertEqual(manager.vaultPaths[2], "C:\\Users\\alice\\Documents\\Vaults")
    }

    func test_vaultPaths_discoveryFindsFirstExistingPath() throws {
        // Create temp directories simulating different vault paths
        let vault1 = tempDir.appendingPathComponent("vault1", isDirectory: true)
        let vault2 = tempDir.appendingPathComponent("vault2", isDirectory: true)
        try FileManager.default.createDirectory(at: vault1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)

        // Create global config with multiple vault paths
        let globalYAML = """
        vaultPaths:
          - \(vault1.path)
          - \(vault2.path)
          - /nonexistent/vault/path
        """
        let globalConfigPath = makeGlobalConfigPath(named: "discovery-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        // The first existing path should be discovered
        let discoveredPath = SettingsManager.discoverVaultPath(from: globalConfigPath)
        XCTAssertEqual(discoveredPath, vault1.path, "Should discover first existing vault path")
    }

    func test_vaultPaths_discoverySkipsNonexistentPaths() throws {
        // Create only the second vault path
        let vault2 = tempDir.appendingPathComponent("vault2", isDirectory: true)
        try FileManager.default.createDirectory(at: vault2, withIntermediateDirectories: true)

        let globalYAML = """
        vaultPaths:
          - /nonexistent/path/1
          - \(vault2.path)
          - /nonexistent/path/2
        """
        let globalConfigPath = makeGlobalConfigPath(named: "skip-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        let discoveredPath = SettingsManager.discoverVaultPath(from: globalConfigPath)
        XCTAssertEqual(discoveredPath, vault2.path, "Should skip nonexistent paths and find existing one")
    }

    func test_vaultPaths_returnsNilWhenNoPathsExist() {
        let globalYAML = """
        vaultPaths:
          - /nonexistent/path/1
          - /nonexistent/path/2
        """
        let globalConfigPath = makeGlobalConfigPath(named: "noexist-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        let discoveredPath = SettingsManager.discoverVaultPath(from: globalConfigPath)
        XCTAssertNil(discoveredPath, "Should return nil when no vault paths exist")
    }

    func test_vaultPath_backwardCompatibility_singleString() {
        // Legacy config with single vaultPath string
        let globalYAML = """
        githubPAT: secret-token
        vaultPath: /legacy/vault/path
        """
        let globalConfigPath = makeGlobalConfigPath(named: "legacy-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)

        // Should be migrated to vaultPaths array
        XCTAssertEqual(manager.vaultPaths.count, 1)
        XCTAssertEqual(manager.vaultPaths[0], "/legacy/vault/path")
    }

    func test_vaultPaths_persistsToDisk() throws {
        let globalConfigPath = makeGlobalConfigPath(named: "persist-test")
        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)

        // Set vault paths
        manager.vaultPaths = ["/path/one", "/path/two"]

        // Create new manager pointing to same config
        let newManager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)
        XCTAssertEqual(newManager.vaultPaths, ["/path/one", "/path/two"], "vaultPaths should persist to disk")
    }

    func test_vaultPaths_emptyArrayWhenNotConfigured() {
        let globalConfigPath = makeGlobalConfigPath(named: "empty-test")
        // No vaultPaths in config
        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)
        XCTAssertTrue(manager.vaultPaths.isEmpty, "Should default to empty array when not configured")
    }

    func test_vaultPath_backwardCompatibility_deprecatedWarning() {
        // This test verifies that when both vaultPath and vaultPaths exist,
        // vaultPaths takes precedence and vaultPath is ignored
        let globalYAML = """
        githubPAT: secret-token
        vaultPath: /legacy/path
        vaultPaths:
          - /new/path/one
          - /new/path/two
        """
        let globalConfigPath = makeGlobalConfigPath(named: "both-test")
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: globalConfigPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? globalYAML.write(to: URL(fileURLWithPath: globalConfigPath), atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: nil, globalConfigPath: globalConfigPath)

        // vaultPaths should take precedence
        XCTAssertEqual(manager.vaultPaths.count, 2)
        XCTAssertEqual(manager.vaultPaths[0], "/new/path/one")
        XCTAssertEqual(manager.vaultPaths[1], "/new/path/two")
        // Legacy vaultPath should not be in the array
        XCTAssertFalse(manager.vaultPaths.contains("/legacy/path"))
    }

    private func makeGlobalConfigPath(named name: String) -> String {
        let appSupportDir = tempDir.appendingPathComponent("AppSupport-\(name)", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        return appSupportDir.appendingPathComponent("settings.yml").path
    }
}
