import SwiftUI
import AppKit

enum SynapseTheme {
    static let canvasTop = Color(white: 0.05)
    static let canvasBottom = Color(white: 0.05)
    static let glowA = Color.clear
    static let glowB = Color.clear
    static let panel = Color(white: 0.07)
    static let panelElevated = Color(white: 0.10)
    static let editorShell = Color(white: 0.07)
    static let row = Color.white.opacity(0.04)
    static let rowBorder = Color.white.opacity(0.06)
    static let tabActive = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.06)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.68)
    static let textMuted = Color.white.opacity(0.45)
    static let accent = Color(red: 0.28, green: 0.66, blue: 0.98)
    static let accentSoft = Color(red: 0.20, green: 0.48, blue: 0.89)
    static let accentGlow = Color.clear
    static let success = Color(red: 0.37, green: 0.83, blue: 0.60)
    static let error = Color(red: 0.95, green: 0.30, blue: 0.30)

    static let editorBackground = NSColor(white: 0.07, alpha: 1)
    static let editorForeground = NSColor(white: 0.92, alpha: 1)
    static let editorMuted = NSColor(white: 0.60, alpha: 1)
    static let editorCodeBackground = NSColor(white: 0.10, alpha: 1)
    static let editorSelection = NSColor(calibratedRed: 0.20, green: 0.44, blue: 0.76, alpha: 0.45)
    static let editorLink = NSColor(calibratedRed: 0.47, green: 0.77, blue: 1.00, alpha: 1)

    // NSColor versions of SwiftUI Color constants for AppKit use
    static let nsPanelElevated = NSColor(white: 0.10, alpha: 1)
    static let nsBorder = NSColor(white: 1.0, alpha: 0.08)
    static let nsTextPrimary = NSColor(white: 1.0, alpha: 0.92)
    static let nsTextSecondary = NSColor(white: 1.0, alpha: 0.68)
    static let nsError = NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.30, alpha: 1)
}

struct AppBackdrop: View {
    var body: some View {
        SynapseTheme.canvasTop.ignoresSafeArea()
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
    func SynapsePanel(radius: CGFloat = 6) -> some View {
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
