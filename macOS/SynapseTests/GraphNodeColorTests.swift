import XCTest
import SwiftUI
@testable import Synapse

/// Tests for graphNodeColor() — the shared graph-node colour helper used by
/// GraphPaneView and GlobalGraphView.  The function has three branches:
///   1. isSelected == true  → accent colour (regardless of isGhost)
///   2. isGhost == true     → textMuted at 60 % opacity
///   3. otherwise           → textSecondary at 80 % opacity
///
/// If these branches regress, graph nodes will be coloured incorrectly and the
/// visual distinction between selected / ghost / normal nodes will be lost.
final class GraphNodeColorTests: XCTestCase {

    // MARK: - Selected node

    func test_selectedNode_returnsAccentColor() {
        let color = graphNodeColor(isSelected: true, isGhost: false)
        XCTAssertEqual(color, SynapseTheme.accent)
    }

    func test_selectedNode_isGhostTrue_stillReturnsAccentColor() {
        // isSelected takes priority over isGhost
        let color = graphNodeColor(isSelected: true, isGhost: true)
        XCTAssertEqual(color, SynapseTheme.accent)
    }

    // MARK: - Ghost node (unresolved wikilink target)

    func test_ghostNode_returnsTextMutedAtReducedOpacity() {
        let color = graphNodeColor(isSelected: false, isGhost: true)
        XCTAssertEqual(color, SynapseTheme.textMuted.opacity(0.6))
    }

    func test_ghostNode_isDifferentFromSelectedNode() {
        let ghost    = graphNodeColor(isSelected: false, isGhost: true)
        let selected = graphNodeColor(isSelected: true,  isGhost: false)
        XCTAssertNotEqual(ghost, selected)
    }

    // MARK: - Regular (non-selected, non-ghost) node

    func test_regularNode_returnsTextSecondaryAtReducedOpacity() {
        let color = graphNodeColor(isSelected: false, isGhost: false)
        XCTAssertEqual(color, SynapseTheme.textSecondary.opacity(0.8))
    }

    func test_regularNode_isDifferentFromGhostNode() {
        let regular = graphNodeColor(isSelected: false, isGhost: false)
        let ghost   = graphNodeColor(isSelected: false, isGhost: true)
        XCTAssertNotEqual(regular, ghost)
    }

    func test_regularNode_isDifferentFromSelectedNode() {
        let regular  = graphNodeColor(isSelected: false, isGhost: false)
        let selected = graphNodeColor(isSelected: true,  isGhost: false)
        XCTAssertNotEqual(regular, selected)
    }

    // MARK: - Determinism / purity

    func test_sameInputProducesSameColor_selectedTrue() {
        XCTAssertEqual(
            graphNodeColor(isSelected: true, isGhost: false),
            graphNodeColor(isSelected: true, isGhost: false)
        )
    }

    func test_sameInputProducesSameColor_ghostTrue() {
        XCTAssertEqual(
            graphNodeColor(isSelected: false, isGhost: true),
            graphNodeColor(isSelected: false, isGhost: true)
        )
    }

    func test_sameInputProducesSameColor_regularNode() {
        XCTAssertEqual(
            graphNodeColor(isSelected: false, isGhost: false),
            graphNodeColor(isSelected: false, isGhost: false)
        )
    }

    // MARK: - All four input combinations produce expected colour branches

    func test_allCombinations_selectedTrueAlwaysReturnsAccent() {
        // Both (true, false) and (true, true) must map to accent
        let tf = graphNodeColor(isSelected: true, isGhost: false)
        let tt = graphNodeColor(isSelected: true, isGhost: true)
        let accent = SynapseTheme.accent
        XCTAssertEqual(tf, accent)
        XCTAssertEqual(tt, accent)
    }

    func test_allCombinations_threeDistinctOutputsForFourInputs() {
        // The four input combinations produce exactly 3 distinct colours:
        //   accent, textMuted.opacity(0.6), textSecondary.opacity(0.8)
        let colors: Set<Color> = [
            graphNodeColor(isSelected: true,  isGhost: false),
            graphNodeColor(isSelected: true,  isGhost: true),
            graphNodeColor(isSelected: false, isGhost: true),
            graphNodeColor(isSelected: false, isGhost: false),
        ]
        XCTAssertEqual(colors.count, 3,
            "Four input combos should yield exactly 3 distinct output colours")
    }
}
