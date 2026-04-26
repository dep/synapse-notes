import SwiftUI

/// A toggle button group for switching between Edit and View modes.
/// Lives above the tab bar and persists across files and app restarts.
struct EditorModeToggle: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            // Edit button
            toggleButton(
                title: "Edit",
                systemImage: "pencil",
                isActive: appState.isEditMode
            ) {
                appState.isEditMode = true
            }
            
            // View button
            toggleButton(
                title: "View",
                systemImage: "eye",
                isActive: !appState.isEditMode
            ) {
                appState.isEditMode = false
            }
        }
        .background(SynapseTheme.editorShell)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(SynapseTheme.border, lineWidth: 1)
        )
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    private func toggleButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? SynapseTheme.textPrimary : SynapseTheme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive ? SynapseTheme.tabActive : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Currently in \(title) mode" : "Switch to \(title) mode")
    }
}

#Preview {
    EditorModeToggle()
        .environmentObject(AppState())
}
