import SwiftUI
import Grape

/// Local Graph pane — renders the selected note and its direct (1-hop) neighbors
/// using a Grape force-directed layout. Shown as a sidebar pane.
struct GraphPaneView: View {
    @EnvironmentObject var appState: AppState

    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: true,
        initialModelTransform: .identity
    )

    private var graph: NoteGraph {
        appState.localGraph() ?? NoteGraph(nodes: [], edges: [])
    }

    private var selectedID: String? {
        guard let file = appState.selectedFile else { return nil }
        return file.deletingPathExtension().lastPathComponent.lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            if graph.nodes.isEmpty {
                emptyState
            } else {
                ForceDirectedGraph(states: graphState) {
                    Series(graph.nodes) { node in
                        let isSelected = node.id == selectedID
                        let isGhost = node.isGhost
                        NodeMark(id: node.id)
                            .symbol(.circle)
                            .symbolSize(radius: isSelected ? 10.0 : 6.0)
                            .foregroundStyle(nodeColor(isSelected: isSelected, isGhost: isGhost))
                            .annotation(node.id, offset: .zero) {
                                Text(node.title)
                                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(
                                        isSelected ? NotedTheme.textPrimary : NotedTheme.textSecondary
                                    )
                                    .lineLimit(1)
                                    .padding(.top, 14)
                            }
                    }
                    Series(graph.edges) { edge in
                        LinkMark(from: edge.fromID, to: edge.toID)
                    }
                } force: {
                    .manyBody(strength: -60)
                    .center()
                    .link(originalLength: 60.0, stiffness: .constant(0.4))
                }
                .graphOverlay { proxy in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .withGraphDragGesture(proxy, of: String.self)
                        .withGraphTapGesture(proxy, of: String.self) { nodeID in
                            openNode(id: nodeID)
                        }
                }
                .background(NotedTheme.panel)
            }
        }
        .onChange(of: appState.selectedFile) { _, _ in
            // Restart simulation when the selected file changes so nodes re-settle
            graphState.isRunning = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 24))
                .foregroundStyle(NotedTheme.textMuted)
            Text(appState.selectedFile == nil ? "No note open" : "No linked notes")
                .font(.system(size: 12))
                .foregroundStyle(NotedTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nodeColor(isSelected: Bool, isGhost: Bool) -> Color {
        if isSelected { return NotedTheme.accent }
        if isGhost { return NotedTheme.textMuted.opacity(0.6) }
        return NotedTheme.textSecondary.opacity(0.8)
    }

    private func openNode(id: String) {
        guard let node = graph.nodes.first(where: { $0.id == id }),
              let url = node.url else { return }
        appState.openFile(url)
    }
}
