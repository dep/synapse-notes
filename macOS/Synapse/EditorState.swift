import Foundation
import AppKit

/// Owns per-editor data: the currently selected file, its content, dirty state,
/// and pending cursor/scroll signals.
/// Views that render the editor (and only need to react to editor changes) should
/// subscribe to this object rather than the monolithic AppState.
final class EditorState: ObservableObject {

    // MARK: - Published Properties

    /// The file currently open in the active editor pane. Nil when no file is open.
    @Published var selectedFile: URL? = nil
    /// The text content of the currently open file.
    @Published var fileContent: String = ""
    /// True when the editor has unsaved changes.
    @Published var isDirty: Bool = false

    // MARK: - Pending Cursor / Scroll Signals

    /// When set, the editor should navigate to this character offset.
    @Published var pendingCursorPosition: Int? = nil
    /// When set, the editor should select / highlight this range.
    @Published var pendingCursorRange: NSRange? = nil
    /// Which pane the pending cursor target is in.
    @Published var pendingCursorTargetPaneIndex: Int? = nil
    /// When set, the editor should scroll to this Y offset.
    @Published var pendingScrollOffsetY: CGFloat? = nil
    /// When set, the editor should pre-populate the search field.
    @Published var pendingSearchQuery: String? = nil
}
