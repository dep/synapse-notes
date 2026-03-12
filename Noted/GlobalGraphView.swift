import SwiftUI
import Grape

/// Global Graph view — full-vault force-directed graph showing all notes and their
/// [[wikilink]] edges. Presented as an overlay sheet from the toolbar.
struct GlobalGraphView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var graphState = ForceDirectedGraphState(
        initialIsRunning: true,
        initialModelTransform: .identity.scale(by: 1.0)
    )

    private var graph: NoteGraph {
        appState.vaultGraph()
    }

    private var selectedID: String? {
        guard let file = appState.selectedFile else { return nil }
        return file.deletingPathExtension().lastPathComponent.lowercased()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            NotedTheme.canvasTop.ignoresSafeArea()

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
                                        isSelected ? NotedTheme.textPrimary : NotedTheme.textSecondary
                                    )
                                    .lineLimit(1)
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
                        .withGraphMagnifyGesture(proxy)
                        .withGraphTapGesture(proxy, of: String.self) { nodeID in
                            openNode(id: nodeID)
                        }
                }
                .ignoresSafeArea()
            }

            // Header bar
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Graph View")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotedTheme.textPrimary)
                        Text("\(graph.nodes.filter { !$0.isGhost }.count) notes · \(graph.edges.count) links")
                            .font(.system(size: 11))
                            .foregroundStyle(NotedTheme.textMuted)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        // Zoom controls
                        HStack(spacing: 4) {
                            Button {
                                graphState.modelTransform.scaling(by: 0.75)
                            } label: {
                                Image(systemName: "minus")
                            }
                            .buttonStyle(ChromeButtonStyle())
                            .help("Zoom out")

                            Button {
                                graphState.modelTransform.scaling(to: 1.0)
                            } label: {
                                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                            }
                            .buttonStyle(ChromeButtonStyle())
                            .help("Reset zoom")

                            Button {
                                graphState.modelTransform.scaling(by: 1.33)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(ChromeButtonStyle())
                            .help("Zoom in")
                        }

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

                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(ChromeButtonStyle())
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("Close Graph (Esc)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(NotedTheme.panelElevated.opacity(0.95))

                Rectangle()
                    .fill(NotedTheme.border)
                    .frame(height: 1)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 36))
                .foregroundStyle(NotedTheme.textMuted)
            Text("No notes in vault")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NotedTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nodeColor(isSelected: Bool, isGhost: Bool) -> Color {
        if isSelected { return NotedTheme.accent }
        if isGhost { return NotedTheme.textMuted.opacity(0.5) }
        return Color(red: 0.47, green: 0.77, blue: 1.00).opacity(0.75) // accentSoft-ish
    }

    private func openNode(id: String) {
        guard let node = graph.nodes.first(where: { $0.id == id }),
              let url = node.url else { return }
        appState.openFile(url)
        isPresented = false
    }
}
