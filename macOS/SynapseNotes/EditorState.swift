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

    // MARK: - Pending Signal Consumption

    /// Returns the pending search query (if any) and clears it.
    func consumePendingSearchQuery() -> String? {
        guard let q = pendingSearchQuery else { return nil }
        pendingSearchQuery = nil
        return q
    }

    /// Returns the pending cursor range if `textView` is editable and the signal targets
    /// `paneIndex` (or no specific pane), clearing the range and pane target.
    func consumePendingCursorRange(for textView: NSTextView, paneIndex: Int) -> NSRange? {
        guard textView.isEditable,
              let range = pendingCursorRange,
              pendingCursorTargetPaneIndex == nil || pendingCursorTargetPaneIndex == paneIndex else { return nil }
        pendingCursorRange = nil
        pendingCursorTargetPaneIndex = nil
        return range
    }

    /// Returns the pending cursor position if `textView` is editable and the signal targets
    /// `paneIndex` (or no specific pane), clearing the position and pane target.
    func consumePendingCursorPosition(for textView: NSTextView, paneIndex: Int) -> Int? {
        guard textView.isEditable,
              let position = pendingCursorPosition,
              pendingCursorTargetPaneIndex == nil || pendingCursorTargetPaneIndex == paneIndex else { return nil }
        pendingCursorPosition = nil
        pendingCursorTargetPaneIndex = nil
        return position
    }

    /// Returns the pending scroll offset if `textView` is editable and the signal targets
    /// `paneIndex` (or no specific pane), clearing the offset.
    func consumePendingScrollOffset(for textView: NSTextView, paneIndex: Int) -> CGFloat? {
        guard textView.isEditable,
              let offset = pendingScrollOffsetY,
              pendingCursorTargetPaneIndex == nil || pendingCursorTargetPaneIndex == paneIndex else { return nil }
        pendingScrollOffsetY = nil
        return offset
    }
}
