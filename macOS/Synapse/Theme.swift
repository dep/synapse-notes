import SwiftUI
import AppKit

enum SynapseTheme {
    // MARK: - Fallback / default values (Synapse (Dark))
    // These are used when no ThemeEnvironment is available (tests, previews, AppKit call-sites).

    static let _canvas         = Color(white: 0.05)
    static let _panel          = Color(white: 0.07)
    static let _panelElevated  = Color(white: 0.10)
    static let _editorShell    = Color(white: 0.07)
    static let _row            = Color.white.opacity(0.04)
    static let _rowBorder      = Color.white.opacity(0.06)
    static let _tabActive      = Color.white.opacity(0.10)
    static let _border         = Color.white.opacity(0.08)
    static let _divider        = Color.white.opacity(0.06)
    static let _textPrimary    = Color.white.opacity(0.92)
    static let _textSecondary  = Color.white.opacity(0.68)
    static let _textMuted      = Color.white.opacity(0.45)
    static let _accent         = Color(red: 0.28, green: 0.66, blue: 0.98)
    static let _accentSoft     = Color(red: 0.20, green: 0.48, blue: 0.89)
    static let _success        = Color(red: 0.37, green: 0.83, blue: 0.60)
    static let _error          = Color(red: 0.95, green: 0.30, blue: 0.30)

    // MARK: - Dynamic accessors (delegate to ThemeEnvironment.shared when available)

    static var canvas:        Color { ThemeEnvironment.shared?.canvas        ?? _canvas }
    static var panel:         Color { ThemeEnvironment.shared?.panel         ?? _panel }
    static var panelElevated: Color { ThemeEnvironment.shared?.panelElevated ?? _panelElevated }
    static var editorShell:   Color { ThemeEnvironment.shared?.panel         ?? _editorShell }
    static var row:           Color { ThemeEnvironment.shared?.row           ?? _row }
    static var rowBorder:     Color { _rowBorder }   // no per-theme token; keep static
    static var tabActive:     Color { _tabActive }   // no per-theme token; keep static
    static var border:        Color { ThemeEnvironment.shared?.border        ?? _border }
    static var divider:       Color { ThemeEnvironment.shared?.divider       ?? _divider }
    static var textPrimary:   Color { ThemeEnvironment.shared?.textPrimary   ?? _textPrimary }
    static var textSecondary: Color { ThemeEnvironment.shared?.textSecondary ?? _textSecondary }
    static var textMuted:     Color { ThemeEnvironment.shared?.textMuted     ?? _textMuted }
    static var accent:        Color { ThemeEnvironment.shared?.accent        ?? _accent }
    static var accentSoft:    Color { ThemeEnvironment.shared?.accentSoft    ?? _accentSoft }
    static var success:       Color { ThemeEnvironment.shared?.success       ?? _success }
    static var error:         Color { ThemeEnvironment.shared?.error         ?? _error }

    // MARK: - NSColor / AppKit values (dynamic)

    static var editorBackground:     NSColor { ThemeEnvironment.shared?.nsEditorBackground     ?? NSColor(white: 0.07, alpha: 1) }
    static var editorForeground:     NSColor { ThemeEnvironment.shared?.nsEditorForeground     ?? NSColor(white: 0.92, alpha: 1) }
    static var editorMuted:          NSColor { NSColor(white: 0.60, alpha: 1) }   // no per-theme token
    static var editorCodeBackground: NSColor { ThemeEnvironment.shared?.nsEditorCodeBackground ?? NSColor(white: 0.10, alpha: 1) }
    static var editorSelection:      NSColor { NSColor(calibratedRed: 0.20, green: 0.44, blue: 0.76, alpha: 0.45) }
    static var editorLink:           NSColor { ThemeEnvironment.shared.map { NSColor($0.accent) } ?? NSColor(calibratedRed: 0.47, green: 0.77, blue: 1.00, alpha: 1) }
    static var editorUnresolvedLink: NSColor { NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.50, alpha: 1) }

    static var nsPanelElevated: NSColor { ThemeEnvironment.shared?.nsPanelElevated ?? NSColor(white: 0.10, alpha: 1) }
    static var nsBorder:        NSColor { ThemeEnvironment.shared?.nsBorder        ?? NSColor(white: 1.0, alpha: 0.08) }
    static var nsTextPrimary:   NSColor { ThemeEnvironment.shared?.nsTextPrimary   ?? NSColor(white: 1.0, alpha: 0.92) }
    static var nsTextSecondary: NSColor { ThemeEnvironment.shared?.nsTextSecondary ?? NSColor(white: 1.0, alpha: 0.68) }
    static var nsError:         NSColor { ThemeEnvironment.shared?.nsError         ?? NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.30, alpha: 1) }

}

struct AppBackdrop: View {
    var body: some View {
        SynapseTheme.canvas.ignoresSafeArea()
    }
}

struct PanelSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(SynapseTheme.panelElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(SynapseTheme.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
            }
    }
}

extension View {
    func synapsePanel(radius: CGFloat = 6) -> some View {
        modifier(PanelSurface(radius: radius))
    }
}

struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(SynapseTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct PrimaryChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SynapseTheme.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .opacity(configuration.isPressed ? 0.88 : 1)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct TinyBadge: View {
    let text: String
    var color: Color = SynapseTheme.textMuted

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
    }
}
