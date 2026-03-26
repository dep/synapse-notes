import Foundation

/// Owns navigation and tab data: tabs, active tab, history-nav state, and split-pane layout.
/// Views that only need to react to tab or navigation changes should subscribe to this object
/// rather than the monolithic AppState.
final class NavigationState: ObservableObject {

    // MARK: - Published Properties

    /// All open tabs in the active pane.
    @Published var tabs: [TabItem] = []
    /// Index into `tabs` of the currently active tab. Nil when no tab is open.
    @Published var activeTabIndex: Int? = nil
    /// True when the user can navigate backwards through history.
    @Published var canGoBack: Bool = false
    /// True when the user can navigate forwards through history.
    @Published var canGoForward: Bool = false
    /// Current split-pane orientation. Nil when no split is active.
    @Published var splitOrientation: SplitOrientation? = nil
    /// Index of the currently focused pane (0 = primary, 1 = secondary).
    @Published var activePaneIndex: Int = 0
}
