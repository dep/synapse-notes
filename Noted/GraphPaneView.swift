import SwiftUI
import Grape

/// Local Graph pane — renders the selected note and its direct (1-hop) neighbors
/// using a Grape force-directed layout. Shown as a sidebar pane.
struct GraphPaneView: View {
    @EnvironmentObject var appState: AppState

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
                // Key on selectedFile so SwiftUI tears down the graph (and its state)
                // entirely when the file changes, preventing stale node positions.
                GraphCanvas(graph: graph, selectedID: selectedID, onOpen: openNode)
                    .id(appState.selectedFile)
                    .background(NotedTheme.panel)
            }
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

/// The actual Grape canvas — isolated into its own view so `@State graphState`
/// is freshly initialised every time the parent changes the `.id(...)` key.
private struct GraphCanvas: View {
    let graph: NoteGraph
    let selectedID: String?
    let onOpen: (String) -> Void

    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: true,
        initialModelTransform: .identity
    )

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                .manyBody(strength: -80)
                .center()
                .link(originalLength: 70.0, stiffness: .constant(0.4))
            }
            .graphOverlay { proxy in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .withGraphDragGesture(proxy, of: String.self)
                    .withGraphMagnifyGesture(proxy)
                    .withGraphTapGesture(proxy, of: String.self) { nodeID in
                        onOpen(nodeID)
                    }
            }

            // Zoom controls
            zoomControls
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                graphState.modelTransform.scaling(by: 0.75)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Zoom out")

            Button {
                graphState.modelTransform.scaling(to: 1.0)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 10))
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Reset zoom")

            Button {
                graphState.modelTransform.scaling(by: 1.33)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Zoom in")
        }
        .padding(6)
    }

    private func nodeColor(isSelected: Bool, isGhost: Bool) -> Color {
        if isSelected { return NotedTheme.accent }
        if isGhost { return NotedTheme.textMuted.opacity(0.6) }
        return NotedTheme.textSecondary.opacity(0.8)
    }
}

private struct GraphZoomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .foregroundStyle(NotedTheme.textMuted)
            .background(
                NotedTheme.panelElevated.opacity(configuration.isPressed ? 1 : 0.85),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }
}
