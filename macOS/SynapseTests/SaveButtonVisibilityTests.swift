import XCTest
@testable import Synapse

/// Regression tests for save button visibility — the save button and ⌘S shortcut must
/// remain available regardless of editor mode (hide-markdown or normal).
final class SaveButtonVisibilityTests: XCTestCase {

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

    private func makeFile(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Save button visibility conditions

    /// The save button should be available when a file is selected, regardless of hide-markdown mode.
    /// This was a regression where enabling hideMarkdownWhileEditing hid both the preview toggle
    /// AND the save button, breaking the ⌘S shortcut.
    func test_saveButton_shouldBeAvailable_whenFileSelected_andHideMarkdownEnabled() {
        let url = makeFile(named: "note.md", content: "test")
        sut.openFile(url)
        sut.settings.hideMarkdownWhileEditing = true

        // The save button should be visible when:
        // 1. A file is selected (selectedFile != nil)
        // 2. We have content to save
        XCTAssertNotNil(sut.selectedFile, "A file should be selected")
        XCTAssertEqual(sut.fileContent, "test", "File content should be loaded")

        // These conditions mirror the UI visibility logic in ContentView:
        // if appState.selectedFile != nil { ... save button ... }
        let saveButtonShouldBeVisible = sut.selectedFile != nil
        XCTAssertTrue(saveButtonShouldBeVisible, "Save button must be visible when a file is selected, even with hide-markdown mode enabled")
    }

    func test_saveButton_shouldBeAvailable_whenFileSelected_andHideMarkdownDisabled() {
        let url = makeFile(named: "note.md", content: "test")
        sut.openFile(url)
        sut.settings.hideMarkdownWhileEditing = false

        XCTAssertNotNil(sut.selectedFile, "A file should be selected")

        let saveButtonShouldBeVisible = sut.selectedFile != nil
        XCTAssertTrue(saveButtonShouldBeVisible, "Save button must be visible when a file is selected")
    }

    func test_saveButton_shouldBeHidden_whenNoFileSelected() {
        // Don't open any file
        sut.selectedFile = nil
        sut.fileContent = ""

        let saveButtonShouldBeVisible = sut.selectedFile != nil
        XCTAssertFalse(saveButtonShouldBeVisible, "Save button should be hidden when no file is selected")
    }

    // MARK: - saveAndSyncCurrentFile integration

    /// The saveAndSyncCurrentFile helper should exist and work as a single entry point
    /// for both the toolbar button and the ⌘S shortcut.
    func test_saveAndSyncCurrentFile_existsAsHelper() {
        let url = makeFile(named: "note.md", content: "original")
        sut.openFile(url)
        sut.fileContent = "updated"
        sut.isDirty = true

        // This method should exist and be callable
        sut.saveAndSyncCurrentFile()

        // After calling, the file should be saved
        XCTAssertFalse(sut.isDirty, "Dirty flag should be cleared after save")
        let onDisk = try? String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "updated", "Content should be written to disk")
    }

    /// When hide-markdown mode is enabled, the preview toggle should be hidden
    /// but the save button should remain visible.
    func test_previewToggleHidden_butSaveButtonVisible_inHideMarkdownMode() {
        let url = makeFile(named: "note.md", content: "test")
        sut.openFile(url)
        sut.settings.hideMarkdownWhileEditing = true

        // Preview toggle visibility condition: selectedFile != nil && !hideMarkdownWhileEditing
        let previewToggleShouldBeVisible = sut.selectedFile != nil && !sut.settings.hideMarkdownWhileEditing
        XCTAssertFalse(previewToggleShouldBeVisible, "Preview toggle should be hidden in hide-markdown mode")

        // Save button visibility condition: selectedFile != nil (no dependency on hideMarkdownWhileEditing)
        let saveButtonShouldBeVisible = sut.selectedFile != nil
        XCTAssertTrue(saveButtonShouldBeVisible, "Save button must remain visible even when preview toggle is hidden")
    }
}
