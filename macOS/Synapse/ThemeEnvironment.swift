import SwiftUI
import Combine

// MARK: - ThemeEnvironment

/// Observable object that tracks the currently active theme and provides reactive color tokens.
/// Inject this as an environment object so views can observe theme changes.
///
/// Usage in views:
///   @EnvironmentObject var themeEnv: ThemeEnvironment
///   SomeView().background(themeEnv.canvas)
///
/// For legacy/static call-sites that use `SynapseTheme.xxx`, the static
/// fallback values in Theme.swift still apply.
final class ThemeEnvironment: ObservableObject {
    @Published private(set) var theme: AppTheme = .synapseDark

    private var cancellable: AnyCancellable?

    // MARK: - Shared singleton (set by SynapseApp at launch)
    /// Set once at app startup so SynapseTheme static vars can delegate to the live theme.
    static weak var shared: ThemeEnvironment?

    init() {}

    /// Wire up the environment to a settings manager so theme changes are reflected automatically.
    func observe(_ settings: SettingsManager) {
        // Register as the shared singleton so SynapseTheme statics can read from us
        ThemeEnvironment.shared = self

        cancellable = settings.$activeThemeName
            .combineLatest(settings.$customThemes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak settings] _, _ in
                guard let self, let settings else { return }
                self.theme = settings.activeTheme
                // Re-apply all AppKit (imperative) color assignments across the app
                refreshAllEditorsForThemeChange()
            }
        // Apply immediately
        theme = settings.activeTheme
    }

    // MARK: - Color accessors (typed, observable)

    var canvas: Color { theme.swiftUIColor(for: "background.primary") ?? SynapseTheme.canvas }
    var panel: Color { theme.swiftUIColor(for: "background.secondary") ?? SynapseTheme.panel }
    var panelElevated: Color { theme.swiftUIColor(for: "background.elevated") ?? SynapseTheme.panelElevated }
    var textPrimary: Color { theme.swiftUIColor(for: "text.primary") ?? SynapseTheme.textPrimary }
    var textSecondary: Color { theme.swiftUIColor(for: "text.secondary") ?? SynapseTheme.textSecondary }
    var textMuted: Color { theme.swiftUIColor(for: "text.muted") ?? SynapseTheme.textMuted }
    var accent: Color { theme.swiftUIColor(for: "accent") ?? SynapseTheme.accent }
    var accentSoft: Color { theme.swiftUIColor(for: "accent.soft") ?? SynapseTheme.accentSoft }
    var border: Color { theme.swiftUIColor(for: "border") ?? SynapseTheme.border }
    var divider: Color { theme.swiftUIColor(for: "divider") ?? SynapseTheme.divider }
    var row: Color { theme.swiftUIColor(for: "row") ?? SynapseTheme.row }
    var success: Color { theme.swiftUIColor(for: "success") ?? SynapseTheme.success }
    var error: Color { theme.swiftUIColor(for: "error") ?? SynapseTheme.error }

    // NSColor variants for AppKit/editor use
    var nsEditorBackground: NSColor {
        theme.nsColor(for: "background.primary") ?? NSColor(white: 0.07, alpha: 1)
    }
    var nsEditorForeground: NSColor {
        theme.nsColor(for: "text.primary") ?? NSColor(white: 0.92, alpha: 1)
    }
    var nsEditorCodeBackground: NSColor {
        theme.nsColor(for: "background.elevated") ?? NSColor(white: 0.10, alpha: 1)
    }

    /// Whether the active theme is a light theme (background luminance > 0.5).
    var isLightTheme: Bool {
        guard let bg = theme.nsColor(for: "background.primary"),
              let rgb = bg.usingColorSpace(.deviceRGB) else { return false }
        // Perceived luminance
        return (rgb.redComponent * 0.299 + rgb.greenComponent * 0.587 + rgb.blueComponent * 0.114) > 0.5
    }

    /// The NSAppearance that matches the active theme.
    var nsAppearance: NSAppearance {
        NSAppearance(named: isLightTheme ? .aqua : .darkAqua) ?? .current
    }
    var nsTextPrimary: NSColor {
        theme.nsColor(for: "text.primary") ?? SynapseTheme.nsTextPrimary
    }
    var nsTextSecondary: NSColor {
        theme.nsColor(for: "text.secondary") ?? SynapseTheme.nsTextSecondary
    }
    var nsBorder: NSColor {
        theme.nsColor(for: "border") ?? SynapseTheme.nsBorder
    }
    var nsPanelElevated: NSColor {
        theme.nsColor(for: "background.elevated") ?? SynapseTheme.nsPanelElevated
    }
    var nsError: NSColor {
        theme.nsColor(for: "error") ?? SynapseTheme.nsError
    }
    var nsAccent: NSColor {
        theme.nsColor(for: "accent") ?? NSColor(SynapseTheme.accent)
    }
}
