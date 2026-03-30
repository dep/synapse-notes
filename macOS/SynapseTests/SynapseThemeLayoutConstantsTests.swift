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

    func test_minLeftSidebarWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.minLeftSidebarWidth, 180 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_maxLeftSidebarWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.maxLeftSidebarWidth, 260 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_minRightSidebarWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.minRightSidebarWidth, 200 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_maxRightSidebarWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.maxRightSidebarWidth, 380 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    // MARK: - Layout: editor and pane constraints

    func test_minEditorWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.minEditorWidth, 400 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_minPaneHeight_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.minPaneHeight, 50 * (SynapseTheme.Layout.phi * SynapseTheme.Layout.phi), accuracy: 0.1)
    }

    func test_fileTreeIndentWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.fileTreeIndentWidth, 10 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_completionPopoverWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.completionPopoverWidth, 260 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_completionPopoverHeight_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.completionPopoverHeight, 160 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_embeddedPanelWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Layout.embeddedPanelWidth, 200 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    // MARK: - Editor: font sizes

    func test_bodyFontSize_is15() {
        XCTAssertEqual(SynapseTheme.Editor.bodyFontSize, 15)
    }

    func test_monoFontSize_is13() {
        XCTAssertEqual(SynapseTheme.Editor.monoFontSize, 13)
    }

    func test_h1FontSize_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Editor.h1FontSize, 15 * (SynapseTheme.Layout.phi * SynapseTheme.Layout.phi), accuracy: 0.1)
    }

    func test_h2FontSize_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Editor.h2FontSize, 15 * SynapseTheme.Layout.phi, accuracy: 0.1)
    }

    func test_h3FontSize_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Editor.h3FontSize, 15 * (SynapseTheme.Layout.phi * 0.8), accuracy: 0.1)
    }

    func test_h4FontSize_is16() {
        XCTAssertEqual(SynapseTheme.Editor.h4FontSize, 16.05, accuracy: 0.1)
    }

    func test_maxInlinePreviewWidth_isExpectedValue() {
        XCTAssertEqual(SynapseTheme.Editor.maxInlinePreviewWidth, 320 * SynapseTheme.Layout.phi, accuracy: 0.1)
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
