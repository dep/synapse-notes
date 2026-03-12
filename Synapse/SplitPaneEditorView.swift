import SwiftUI

/// Renders either a single editor pane or two independent panes side-by-side / top-bottom.
struct SplitPaneEditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let orientation = appState.splitOrientation {
            switch orientation {
            case .vertical:
                HSplitView {
                    pane(index: 0)
                    pane(index: 1)
                }
            case .horizontal:
                VSplitView {
                    pane(index: 0)
                    pane(index: 1)
                }
            }
        } else {
            singlePane
        }
    }

    private var singlePane: some View {
        VStack(spacing: 0) {
            TabBarView()
                .environmentObject(appState)
            editorContent(for: appState.activeTab, paneIndex: 0)
        }
    }

    @ViewBuilder
    private func pane(index: Int) -> some View {
        PaneView(paneIndex: index)
            .environmentObject(appState)
            .frame(minWidth: 300)
    }
}

/// A single independent editor pane with its own tab bar, active state indicator, and close button.
struct PaneView: View {
    @EnvironmentObject var appState: AppState
    let paneIndex: Int

    private var isActive: Bool { appState.activePaneIndex == paneIndex }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            if isActive {
                editorContent(for: appState.activeTab, paneIndex: paneIndex)
                    .background(SynapseTheme.editorShell)
            } else {
                inactiveContent
                    .background(SynapseTheme.editorShell)
                    .onTapGesture { appState.focusPane(paneIndex) }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? SynapseTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private var inactiveContent: some View {
        let pane = appState.inactivePane(paneIndex)
        return EditorView(paneIndex: paneIndex, readOnlyFile: pane.selectedFile, readOnlyContent: pane.fileContent)
    }

    private var paneHeader: some View {
        HStack(spacing: 0) {
            if appState.activePaneIndex == paneIndex {
                TabBarView()
                    .environmentObject(appState)
            } else {
                InactivePaneTabBar(paneIndex: paneIndex)
                    .environmentObject(appState)
            }

            Spacer(minLength: 0)

            Button(action: { appState.closePane(paneIndex) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .help("Close Pane")
        }
        .frame(height: 32)
        .background(SynapseTheme.editorShell)
        .overlay(
            Rectangle()
                .fill(SynapseTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .onTapGesture {
            appState.focusPane(paneIndex)
        }
    }
}

/// Shows the tab bar for an inactive pane (read from snapshot).
/// Since inactive pane state is stored in paneStates (private to AppState),
/// we expose a computed property on AppState for inactive pane display info.
struct InactivePaneTabBar: View {
    @EnvironmentObject var appState: AppState
    let paneIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(appState.inactivePane(paneIndex).tabs.enumerated()), id: \.offset) { index, tab in
                let isActive = index == appState.inactivePane(paneIndex).activeTabIndex
                Text(tab.displayName)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isActive ? SynapseTheme.textPrimary : SynapseTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 32)
                    .background(isActive ? SynapseTheme.tabActive : Color.clear)
                    .onTapGesture {
                        appState.focusPane(paneIndex)
                    }
            }
            Spacer()
        }
    }
}


@ViewBuilder
func editorContent(for tab: TabItem?, paneIndex: Int) -> some View {
    Group {
        if let tab, tab.isGraph {
            GlobalGraphView()
        } else if let tab, let tagName = tab.tagName {
            TagPageView(tag: tagName)
                .background(SynapseTheme.editorShell)
        } else {
            EditorView(paneIndex: paneIndex)
                .background(SynapseTheme.editorShell)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
