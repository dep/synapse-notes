import XCTest
@testable import Synapse

final class SidebarNotePanePersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    func test_vaultSettings_loadDroppedNotePaneFromGlobalSidebarLayout() throws {
        let vaultDir = tempDir.appendingPathComponent("Vault", isDirectory: true)
        let notedDir = vaultDir.appendingPathComponent(".noted", isDirectory: true)
        try FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)

        let noteURL = vaultDir.appendingPathComponent("Reference.md")
        try "# Reference".write(to: noteURL, atomically: true, encoding: .utf8)

        let vaultYAML = """
        onBootCommand: ''
        fileExtensionFilter: '*.md'
        templatesDirectory: templates
        autoSave: true
        autoPush: false
        pinnedItems: []
        """
        try vaultYAML.write(to: notedDir.appendingPathComponent("settings.yml"), atomically: true, encoding: .utf8)

        let globalConfigPath = tempDir.appendingPathComponent("global-settings.yml")
        let globalYAML = """
        sidebarPaneAssignments:
          \(FixedSidebar.leftID.uuidString):
            - files
            - links
            - type: note
              id: 11111111-1111-1111-1111-111111111111
              path: \(noteURL.path)
        """
        try globalYAML.write(to: globalConfigPath, atomically: true, encoding: .utf8)

        let manager = SettingsManager(vaultRoot: vaultDir, globalConfigPath: globalConfigPath.path)
        let leftSidebar = try XCTUnwrap(manager.sidebars.first { $0.id == FixedSidebar.leftID })

        XCTAssertEqual(leftSidebar.panes.count, 3)
        XCTAssertEqual(leftSidebar.panes.map(\.title), ["Files", "Related", "Reference"])
    }
}
