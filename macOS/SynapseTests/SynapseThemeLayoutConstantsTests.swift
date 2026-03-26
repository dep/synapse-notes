import XCTest
import SwiftUI
import AppKit
@testable import Synapse

/// Tests for SynapseTheme layout/editor constants and colour values.
///
/// These constants drive every pixel of the Synapse UI: sidebar widths, editor
/// min-width, font sizes for heading levels, colour opacity values, etc.
/// Accidental changes to any of these silently break layouts or accessibility
/// contrast; pinning them with assertions acts as a regression guard.
final class SynapseThemeLayoutConstantsTests: XCTestCase {

    // MARK: - Layout: sidebar widths

    func test_minLeftSidebarWidth_isLessThanMaxLeftSidebarWidth() {
        XCTAssertLessThan(SynapseTheme.Layout.minLeftSidebarWidth,
                          SynapseTheme.Layout.maxLeftSidebarWidth,
                          "Min left sidebar width must be less than max")
    }

    func test_minRightSidebarWidth_isLessThanMaxRightSidebarWidth() {
        XCTAssertLessThan(SynapseTheme.Layout.minRightSidebarWidth,
                          SynapseTheme.Layout.maxRightSidebarWidth,
                          "Min right sidebar width must be less than max")
    }

    func test_minLeftSidebarWidth_is220() {
        XCTAssertEqual(SynapseTheme.Layout.minLeftSidebarWidth, 220)
    }

    func test_maxLeftSidebarWidth_is420() {
        XCTAssertEqual(SynapseTheme.Layout.maxLeftSidebarWidth, 420)
    }

    func test_minRightSidebarWidth_is280() {
        XCTAssertEqual(SynapseTheme.Layout.minRightSidebarWidth, 280)
    }

    func test_maxRightSidebarWidth_is620() {
        XCTAssertEqual(SynapseTheme.Layout.maxRightSidebarWidth, 620)
    }

    // MARK: - Layout: editor and pane constraints

    func test_minEditorWidth_is420() {
        XCTAssertEqual(SynapseTheme.Layout.minEditorWidth, 420)
    }

    func test_minPaneHeight_is80() {
        XCTAssertEqual(SynapseTheme.Layout.minPaneHeight, 80)
    }

    func test_fileTreeIndentWidth_is16() {
        XCTAssertEqual(SynapseTheme.Layout.fileTreeIndentWidth, 16)
    }

    func test_completionPopoverWidth_is420() {
        XCTAssertEqual(SynapseTheme.Layout.completionPopoverWidth, 420)
    }

    func test_completionPopoverHeight_is260() {
        XCTAssertEqual(SynapseTheme.Layout.completionPopoverHeight, 260)
    }

    func test_embeddedPanelWidth_is320() {
        XCTAssertEqual(SynapseTheme.Layout.embeddedPanelWidth, 320)
    }

    // MARK: - Editor: font sizes

    func test_bodyFontSize_is15() {
        XCTAssertEqual(SynapseTheme.Editor.bodyFontSize, 15)
    }

    func test_monoFontSize_is13() {
        XCTAssertEqual(SynapseTheme.Editor.monoFontSize, 13)
    }

    func test_h1FontSize_is28() {
        XCTAssertEqual(SynapseTheme.Editor.h1FontSize, 28)
    }

    func test_h2FontSize_is22() {
        XCTAssertEqual(SynapseTheme.Editor.h2FontSize, 22)
    }

    func test_h3FontSize_is18() {
        XCTAssertEqual(SynapseTheme.Editor.h3FontSize, 18)
    }

    func test_h4FontSize_is16() {
        XCTAssertEqual(SynapseTheme.Editor.h4FontSize, 16)
    }

    func test_maxInlinePreviewWidth_is520() {
        XCTAssertEqual(SynapseTheme.Editor.maxInlinePreviewWidth, 520)
    }

    // MARK: - Heading sizes must decrease monotonically from h1 to h4

    func test_headingFontSizes_decreaseFromH1ToH4() {
        XCTAssertGreaterThan(SynapseTheme.Editor.h1FontSize, SynapseTheme.Editor.h2FontSize,
                             "H1 must be larger than H2")
        XCTAssertGreaterThan(SynapseTheme.Editor.h2FontSize, SynapseTheme.Editor.h3FontSize,
                             "H2 must be larger than H3")
        XCTAssertGreaterThan(SynapseTheme.Editor.h3FontSize, SynapseTheme.Editor.h4FontSize,
                             "H3 must be larger than H4")
    }

    func test_bodyFontSize_isBetweenMonoAndH4() {
        XCTAssertGreaterThanOrEqual(SynapseTheme.Editor.bodyFontSize, SynapseTheme.Editor.monoFontSize,
                                    "Body font must be at least as large as mono font")
        XCTAssertLessThanOrEqual(SynapseTheme.Editor.bodyFontSize, SynapseTheme.Editor.h4FontSize,
                                 "Body font must be no larger than h4 heading")
    }

    // MARK: - SynapseTheme NSColor values

    func test_editorBackground_alphaIsOne() {
        XCTAssertEqual(SynapseTheme.editorBackground.alphaComponent, 1.0, accuracy: 0.001,
                       "Editor background must be fully opaque")
    }

    func test_editorForeground_alphaIsOne() {
        XCTAssertEqual(SynapseTheme.editorForeground.alphaComponent, 1.0, accuracy: 0.001,
                       "Editor foreground must be fully opaque")
    }

    func test_editorMuted_alphaIsOne() {
        XCTAssertEqual(SynapseTheme.editorMuted.alphaComponent, 1.0, accuracy: 0.001,
                       "Editor muted colour must be fully opaque")
    }

    func test_editorBackground_isDarkColor() {
        // The editor uses a dark theme; background lightness must be low.
        // `whiteComponent` is not valid on sRGB NSColors; use RGB channels instead.
        guard let avg = averageSRGBChannelBrightness(SynapseTheme.editorBackground) else {
            XCTFail("Editor background must convert to sRGB")
            return
        }
        XCTAssertLessThan(avg, 0.2, "Editor background must be a dark colour (avg sRGB channel < 0.2) — got: \(avg)")
    }

    func test_editorForeground_isLightColor() {
        // Foreground must contrast against the dark background.
        guard let avg = averageSRGBChannelBrightness(SynapseTheme.editorForeground) else {
            XCTFail("Editor foreground must convert to sRGB")
            return
        }
        XCTAssertGreaterThan(avg, 0.8, "Editor foreground must be a light colour (avg sRGB channel > 0.8) — got: \(avg)")
    }

    func test_editorSelection_hasNonTrivialAlpha() {
        XCTAssertGreaterThan(SynapseTheme.editorSelection.alphaComponent, 0.1,
                             "Selection colour alpha must be visible (> 0.1)")
        XCTAssertLessThan(SynapseTheme.editorSelection.alphaComponent, 1.0,
                          "Selection colour should be semi-transparent (< 1.0) to show content underneath")
    }

    func test_editorLink_alphaIsOne() {
        XCTAssertEqual(SynapseTheme.editorLink.alphaComponent, 1.0, accuracy: 0.001,
                       "Link colour must be fully opaque")
    }

    func test_editorUnresolvedLink_alphaIsOne() {
        XCTAssertEqual(SynapseTheme.editorUnresolvedLink.alphaComponent, 1.0, accuracy: 0.001,
                       "Unresolved link colour must be fully opaque")
    }

    func test_editorLink_andUnresolvedLink_areDifferent() {
        let link = SynapseTheme.editorLink.usingColorSpace(.sRGB)
        let unresolved = SynapseTheme.editorUnresolvedLink.usingColorSpace(.sRGB)
        // They must not be the same colour; the difference gives visual feedback about link state.
        XCTAssertNotEqual(link?.redComponent, unresolved?.redComponent,
                          "Resolved and unresolved link colours must differ so users can distinguish them")
    }

    // MARK: - graphNodeColor utility

    func test_graphNodeColor_selected_returnsAccentColor() {
        // We can't do a pixel-perfect comparison on Color, but we can verify the function
        // returns distinct values for different states.
        let selected = graphNodeColor(isSelected: true, isGhost: false)
        let normal   = graphNodeColor(isSelected: false, isGhost: false)
        let ghost    = graphNodeColor(isSelected: false, isGhost: true)

        // All three states should produce distinct colors.
        XCTAssertNotEqual("\(selected)", "\(normal)",  "Selected node color must differ from normal")
        XCTAssertNotEqual("\(normal)",   "\(ghost)",   "Normal and ghost node colors must differ")
        XCTAssertNotEqual("\(selected)", "\(ghost)",   "Selected and ghost node colors must differ")
    }

    func test_graphNodeColor_selectedTakesPrecedenceOverGhost() {
        // When both isSelected and isGhost are true, selected wins (returns accent).
        let both   = graphNodeColor(isSelected: true, isGhost: true)
        let selOnly = graphNodeColor(isSelected: true, isGhost: false)
        XCTAssertEqual("\(both)", "\(selOnly)",
                       "isSelected=true should always return the accent color regardless of isGhost")
    }

    /// Average of sRGB R, G, B in 0...1. `whiteComponent` is invalid on non-grayscale sRGB `NSColor`s.
    private func averageSRGBChannelBrightness(_ color: NSColor) -> CGFloat? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return (srgb.redComponent + srgb.greenComponent + srgb.blueComponent) / 3
    }
}
