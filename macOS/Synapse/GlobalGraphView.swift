import SwiftUI
import Grape
import AppKit

/// Global Graph view — full-vault force-directed graph showing all notes and their
/// [[wikilink]] edges. Presented as an overlay sheet from the toolbar.
struct GlobalGraphView: View {
    @EnvironmentObject var appState: AppState

    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: true,
        initialModelTransform: .identity.scale(by: 1.0)
    )
    @State private var scrollMonitor: Any?
    
    // Cached graph — only recomputed when vault contents change, not on every frame
    @State private var graph: NoteGraph = NoteGraph(nodes: [], edges: [])

    private var selectedID: String? {
        guard let file = appState.selectedFile else { return nil }
        return file.deletingPathExtension().lastPathComponent.lowercased()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            SynapseTheme.canvas.ignoresSafeArea()

            if graph.nodes.isEmpty {
                emptyState
            } else {
                ForceDirectedGraph(states: graphState) {
                    Series(graph.nodes) { node in
                        let isSelected = node.id == selectedID
                        let isGhost = node.isGhost
                        NodeMark(id: node.id)
                            .symbol(.circle)
                            .symbolSize(radius: isSelected ? 12.0 : 7.0)
                            .foregroundStyle(nodeColor(isSelected: isSelected, isGhost: isGhost))
                            .annotation(node.id, offset: .zero) {
                                Text(node.title)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular, design: .rounded))
                                    .foregroundStyle(
                                        isSelected ? SynapseTheme.textPrimary : SynapseTheme.textSecondary
                                    )
                                    .lineLimit(1)
                                    // Cap label width so long filenames don't distort the layout
                                    .frame(maxWidth: 100, alignment: .center)
                                    .padding(.top, 16)
                            }
                    }
                    Series(graph.edges) { edge in
                        LinkMark(from: edge.fromID, to: edge.toID)
                    }
                } force: {
                    .manyBody(strength: -30)
                    .center()
                    .link(
                        originalLength: 80.0,
                        stiffness: .weightedByDegree { _, _ in 0.6 }
                    )
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
                .ignoresSafeArea()
            }

            // Header bar
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("\(graph.nodes.filter { !$0.isGhost }.count) notes · \(graph.edges.count) links")
                        .font(.system(size: 11))
                        .foregroundStyle(SynapseTheme.textMuted)

                    Spacer()

                    HStack(spacing: 6) {
                        // Zoom controls — use GraphZoomButtonStyle for uniform sizing
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

                        Divider()
                            .frame(height: 16)
                            .opacity(0.4)

                        Button {
                            graphState.isRunning.toggle()
                        } label: {
                            Image(systemName: graphState.isRunning ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(ChromeButtonStyle())
                        .help(graphState.isRunning ? "Pause simulation" : "Resume simulation")


                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(SynapseTheme.panelElevated.opacity(0.95))

                Rectangle()
                    .fill(SynapseTheme.border)
                    .frame(height: 1)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            refresh()
            installScrollMonitor()
        }
        // 4B: Use targeted notifications so only actual graph/file changes trigger rebuild.
        // Editing a note that adds no wiki-link changes does NOT recompute the graph.
        .onReceive(NotificationCenter.default.publisher(for: .graphDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .filesDidChange)) { _ in refresh() }
        .onDisappear { removeScrollMonitor() }
    }

    private func refresh() {
        graph = appState.vaultGraph()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 36))
                .foregroundStyle(SynapseTheme.textMuted)
            Text("No notes in vault")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SynapseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nodeColor(isSelected: Bool, isGhost: Bool) -> Color {
        graphNodeColor(isSelected: isSelected, isGhost: isGhost)
    }

    private func openNode(id: String) {
        guard let node = graph.nodes.first(where: { $0.id == id }),
              let url = node.url else { return }
        appState.openFile(url)
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.momentumPhase == [] else { return event }
            let factor = pow(1.0015, event.scrollingDeltaY)
            graphState.modelTransform.scaling(by: factor)
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
}
