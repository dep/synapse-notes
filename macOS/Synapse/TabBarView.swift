import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeEnv: ThemeEnvironment

    var body: some View {
        HStack(spacing: 0) {
            if appState.tabs.isEmpty {
                // Empty state - show placeholder or nothing
                EmptyView()
            } else {
                ForEach(Array(appState.tabs.enumerated()), id: \.offset) { index, tab in
                    TabItemView(
                        tab: tab,
                        displayName: tab.displayName,
                        isActive: index == appState.activeTabIndex,
                        onSelect: { appState.switchTab(to: index) },
                        onClose: { appState.closeTab(at: index) }
                    )
                    .id(index)
                }
            }

            Spacer()
        }
        .frame(height: 20 * SynapseTheme.Layout.phi)
        .background(SynapseTheme.editorShell)
        .overlay(
            Rectangle()
                .fill(SynapseTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct TabItemView: View {
    let tab: TabItem
    let displayName: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(displayName)
                .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isActive ? SynapseTheme.textPrimary : SynapseTheme.textSecondary)

            if isHovered || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SynapseTheme.textMuted)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, SynapseTheme.Layout.spaceMedium)
        .padding(.vertical, 6)
        .frame(height: 20 * SynapseTheme.Layout.phi)
        .background(
            isActive ? SynapseTheme.tabActive : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onSelect()
        }
        .modifier(TabDragModifier(fileURL: tab.fileURL))
    }
}

// MARK: - Tab Drag Modifier
/// Enables dragging tabs to folders in the file tree to move notes.
/// Uses a separate provider that doesn't set isFileTreeDragActive,
/// allowing FileTreeView to handle the drop as a file move operation.

private struct TabDragModifier: ViewModifier {
    let fileURL: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let fileURL {
            content.onDrag {
                // Use tabFileItemProvider instead of sidebarFileItemProvider
                // This allows dragging tabs to folders without triggering the
                // isFileTreeDragActive flag that prevents file moves
                tabFileItemProvider(for: fileURL)
            }
        } else {
            content
        }
    }
}

#Preview {
    TabBarView()
        .environmentObject(AppState())
}
