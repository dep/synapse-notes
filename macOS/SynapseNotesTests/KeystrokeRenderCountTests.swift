import XCTest
import SwiftUI
@testable import Synapse

/// End-to-end render-count regression for #258, hosted in a real NSHostingView.
///
/// The existing AppStateObservationSplitTests prove `objectWillChange` silence at the
/// Combine level; these tests prove the consequence under actual SwiftUI hosting: the
/// body of a view observing the AppState monolith (ContentView's shape) is NOT
/// re-evaluated by keystroke-frequency EditorState mutations, while a view observing
/// EditorState (the editor leaves' shape) IS — so the harness cannot false-pass.
final class KeystrokeRenderCountTests: XCTestCase {

    /// Body-evaluation tally shared by the probe views below.
    private final class RenderTally {
        private var counts: [String: Int] = [:]
        func tick(_ key: String) { counts[key, default: 0] += 1 }
        func count(_ key: String) -> Int { counts[key] ?? 0 }
    }

    /// Stand-in for any view observing the AppState monolith (e.g. ContentView's
    /// 1,400-line body): typing must never re-evaluate this body.
    private struct AppStateProbe: View {
        @EnvironmentObject var appState: AppState
        let tally: RenderTally
        var body: some View {
            tally.tick("appState")
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Stand-in for the editor leaf views (EditorView, UnsavedIndicator,
    /// SaveHeaderButton): typing SHOULD re-evaluate this body, proving the
    /// hosting harness actually detects invalidations.
    private struct EditorStateProbe: View {
        @EnvironmentObject var editorState: EditorState
        let tally: RenderTally
        var body: some View {
            tally.tick("editorState")
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private var window: NSWindow!

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    /// Hosts both probes in an offscreen window with the same environment-object
    /// injection SynapseNotesApp uses (AppState plus its editorState sub-object).
    private func host(_ appState: AppState, tally: RenderTally) {
        let root = VStack(spacing: 0) {
            AppStateProbe(tally: tally)
            EditorStateProbe(tally: tally)
        }
        .environmentObject(appState)
        .environmentObject(appState.editorState)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        pump()
    }

    /// Lets SwiftUI coalesce pending publishes and run its render pass.
    private func pump(_ interval: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    func test_typingAndCaretSignals_doNotReEvaluateAppStateObserverBody() {
        let appState = AppState()
        let tally = RenderTally()
        host(appState, tally: tally)

        XCTAssertGreaterThan(tally.count("appState"), 0,
                             "Harness sanity: hosting must evaluate the probe bodies at least once")
        let appStateBaseline = tally.count("appState")
        let editorStateBaseline = tally.count("editorState")

        // Simulate five keystrokes plus the caret/scroll signals the editor emits.
        for i in 0..<5 {
            appState.editorState.fileContent += "x"
            appState.editorState.isDirty = true
            appState.editorState.pendingCursorPosition = i
            pump()
        }

        XCTAssertEqual(tally.count("appState"), appStateBaseline,
                       "Typing re-evaluated an AppState-observing body — the keystroke path is publishing on AppState again (#258 regression)")
        XCTAssertGreaterThan(tally.count("editorState"), editorStateBaseline,
                             "Harness sanity: EditorState observers must re-render on typing, otherwise this test proves nothing")
    }

    func test_lowFrequencyAppStatePublish_stillInvalidatesAppStateObserverBody() {
        let appState = AppState()
        let tally = RenderTally()
        host(appState, tally: tally)

        let baseline = tally.count("appState")
        // Control: a genuine low-frequency @Published write (search toggle) must
        // still invalidate AppState observers — proves the probe is live, so the
        // flat count above cannot come from a dead binding.
        appState.isSearchPresented = true
        pump()

        XCTAssertGreaterThan(tally.count("appState"), baseline,
                             "Low-frequency AppState publishes must still re-render AppState observers")
    }
}
