import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Key Codes

/// Named constants for macOS virtual key codes used across the app.
enum KeyCode {
    static let tab: UInt16         = 48
    static let escape: UInt16      = 53
    static let returnKey: UInt16   = 36
    static let numpadEnter: UInt16 = 76
    static let downArrow: UInt16   = 125
    static let upArrow: UInt16     = 126
    static let leftArrow: UInt16   = 123
    static let rightArrow: UInt16  = 124
}

// MARK: - App Constants

enum AppConstants {
    /// Vault-local config directory name
    static let vaultConfigDirectory = ".synapse"
    /// Image paste directory name
    static let imagesPasteDirectory = ".images"
    /// Default file extension filter
    static let defaultFileExtensionFilter = "*.md, *.txt"
    /// Default templates directory name
    static let defaultTemplatesDirectory = "templates"
    /// Default daily notes folder name
    static let defaultDailyNotesFolder = "daily"
    /// Default git branch name
    static let defaultBranchName = "main"
    /// Settings filename
    static let settingsFilename = "settings.yml"
    /// Fallback URL for unsaved files
    static let unsavedFileURL = URL(fileURLWithPath: "/tmp/unsaved.md")
    /// Maximum recent files to keep
    static let maxRecentFiles = 40
    /// Maximum search matches
    static let maxSearchMatches = 2000
    /// Maximum link token length for wiki-link completion
    static let maxLinkTokenLength = 120
    /// Git paths to search
    static let gitSearchPaths = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
}

// MARK: - Layout Constants

extension SynapseTheme {
    enum Layout {
        static let minLeftSidebarWidth: CGFloat = 220
        static let maxLeftSidebarWidth: CGFloat = 420
        static let minRightSidebarWidth: CGFloat = 280
        static let maxRightSidebarWidth: CGFloat = 620
        static let minEditorWidth: CGFloat = 420
        static let minPaneHeight: CGFloat = 80
        static let fileTreeIndentWidth: CGFloat = 16
        static let completionPopoverWidth: CGFloat = 420
        static let completionPopoverHeight: CGFloat = 260
        static let embeddedPanelWidth: CGFloat = 320
    }

    enum Editor {
        static let bodyFontSize: CGFloat = 15
        static let monoFontSize: CGFloat = 13
        static let h1FontSize: CGFloat = 28
        static let h2FontSize: CGFloat = 22
        static let h3FontSize: CGFloat = 18
        static let h4FontSize: CGFloat = 16
        static let maxInlinePreviewWidth: CGFloat = 520
    }
}

// MARK: - Sidebar Auto-Collapse

extension SynapseTheme.Layout {
    /// Window width above which all three sidebars are shown expanded.
    static let allSidebarsExpandedWidth: CGFloat = 1480
    /// Window width above which left + right1 are shown (right2 collapsed).
    static let twoSidebarsExpandedWidth: CGFloat = 1125
    /// Window width above which only the left sidebar is shown (right1 + right2 collapsed).
    static let oneSidebarExpandedWidth: CGFloat = 900
}

/// Returns the set of fixed sidebar IDs that should be auto-collapsed for the given window width.
///
/// Breakpoints (inclusive lower bound):
///   ≥ 1480  → all three sidebars expanded  (empty set returned)
///   ≥ 1125  → left + right1 expanded; right2 collapsed
///   ≥  900  → left expanded only; right1 + right2 collapsed
///    < 900  → all three sidebars collapsed
func sidebarAutoCollapseIDs(forWindowWidth width: CGFloat) -> Set<UUID> {
    if width >= SynapseTheme.Layout.allSidebarsExpandedWidth {
        return []
    } else if width >= SynapseTheme.Layout.twoSidebarsExpandedWidth {
        return [FixedSidebar.right2ID]
    } else if width >= SynapseTheme.Layout.oneSidebarExpandedWidth {
        return [FixedSidebar.right1ID, FixedSidebar.right2ID]
    } else {
        return [FixedSidebar.leftID, FixedSidebar.right1ID, FixedSidebar.right2ID]
    }
}

// MARK: - Graph Utilities

/// Shared node color logic for graph views.
func graphNodeColor(isSelected: Bool, isGhost: Bool) -> Color {
    if isSelected { return SynapseTheme.accent }
    if isGhost { return SynapseTheme.textMuted.opacity(0.6) }
    return SynapseTheme.textSecondary.opacity(0.8)
}
