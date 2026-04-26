import SwiftUI
import Grape
import AppKit

/// Local Graph pane — renders the selected note and its direct (1-hop) neighbors
/// using a Grape force-directed layout. Shown as a sidebar pane.
struct GraphPaneView: View {
    @EnvironmentObject var appState: AppState

    // Cached graph — only recomputed when selectedFile or vault contents change, not on every keystroke
    @State private var graph: NoteGraph = NoteGraph(nodes: [], edges: [])

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
                    .background(SynapseTheme.panel)
            }
        }
        .onAppear { refresh() }
        .onChange(of: appState.selectedFile) { _ in refresh() }
        .onChange(of: appState.allFiles) { _ in refresh() }
        .onChange(of: appState.lastContentChange) { _ in refresh() }
    }

    private func refresh() {
        graph = appState.localGraph() ?? NoteGraph(nodes: [], edges: [])
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 24))
                .foregroundStyle(SynapseTheme.textMuted)
            Text(appState.selectedFile == nil ? "No note open" : "No linked notes")
                .font(.system(size: 12))
                .foregroundStyle(SynapseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var scrollMonitor: Any?
    @State private var isHovered = false

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
                                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(
                                    isSelected ? Color.white : SynapseTheme.textPrimary
                                )
                                .lineLimit(1)
                                .frame(maxWidth: 260, alignment: .center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                                .padding(.top, 32)
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
                    .withGraphTapGesture(proxy, of: String.self) { nodeID in
                        onOpen(nodeID)
                    }
            }

            // Zoom controls
            zoomControls
        }
        .onHover { isHovered = $0 }
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                graphState.modelTransform.scaling(by: 0.75)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Zoom out")

            Button {
                graphState.modelTransform.scaling(to: 1.0)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Reset zoom")

            Button {
                graphState.modelTransform.scaling(by: 1.33)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(GraphZoomButtonStyle())
            .help("Zoom in")
        }
        .padding(6)
    }

    private func nodeColor(isSelected: Bool, isGhost: Bool) -> Color {
        graphNodeColor(isSelected: isSelected, isGhost: isGhost)
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovered, event.momentumPhase == [] else { return event }
            let factor = pow(1.0015, event.scrollingDeltaY)
            graphState.modelTransform.scaling(by: factor)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
}

// MARK: - Shared zoom button style (also used by GlobalGraphView)

struct GraphZoomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
            .foregroundStyle(SynapseTheme.textSecondary)
            .background(
                SynapseTheme.panelElevated.opacity(configuration.isPressed ? 1 : 0.85),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}
