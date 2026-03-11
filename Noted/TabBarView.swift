import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            if appState.tabs.isEmpty {
                // Empty state - show placeholder or nothing
                EmptyView()
            } else {
                ForEach(Array(appState.tabs.enumerated()), id: \.offset) { index, url in
                    TabItemView(
                        fileName: url.lastPathComponent,
                        isActive: index == appState.activeTabIndex,
                        onSelect: { appState.switchTab(to: index) },
                        onClose: { appState.closeTab(at: index) }
                    )
                    .id(index)
                }
            }
            
            Spacer()
        }
        .frame(height: 32)
        .background(NotedTheme.editorShell)
        .overlay(
            Rectangle()
                .fill(NotedTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct TabItemView: View {
    let fileName: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text(fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? NotedTheme.textPrimary : NotedTheme.textMuted)
                    .lineLimit(1)
                
                if isActive || isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NotedTheme.textMuted)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onClose)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? NotedTheme.row : Color.clear)
            .overlay(
                Rectangle()
                    .fill(NotedTheme.border)
                    .frame(width: 1),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .fill(isActive ? NotedTheme.accent : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
