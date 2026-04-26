import XCTest
import Combine
@testable import Synapse

final class AppStateSettingsPropagationTests: XCTestCase {
    private var tempDir: URL!
    private var configFilePath: String!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configFilePath = tempDir.appendingPathComponent("Synapse-settings.json").path
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_hideMarkdownChange_republishesThroughAppState_whenEditModeAlreadyEnabled() {
        let settings = SettingsManager(configPath: configFilePath)
        settings.defaultEditMode = true
        settings.hideMarkdownWhileEditing = false

        let appState = AppState(settings: settings)
        XCTAssertTrue(appState.isEditMode, "Precondition: edit mode stays unchanged during the toggle")

        let changeExpectation = expectation(description: "AppState republishes nested settings changes after the new value is available")
        var observedUpdatedValue = false
        appState.objectWillChange
            .sink { _ in
                if appState.settings.hideMarkdownWhileEditing && !observedUpdatedValue {
                    observedUpdatedValue = true
                    changeExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        settings.hideMarkdownWhileEditing = true

        wait(for: [changeExpectation], timeout: 1.0)
    }

    func test_editorFontChange_republishesThroughAppState() {
        let settings = SettingsManager(configPath: configFilePath)
        let appState = AppState(settings: settings)

        let changeExpectation = expectation(description: "AppState republishes nested editor font changes")
        var observedUpdatedValue = false
        appState.objectWillChange
            .sink { _ in
                if appState.settings.editorBodyFontFamily == "Chalkboard SE" && !observedUpdatedValue {
                    observedUpdatedValue = true
                    changeExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        settings.editorBodyFontFamily = "Chalkboard SE"

        wait(for: [changeExpectation], timeout: 1.0)
    }
}
