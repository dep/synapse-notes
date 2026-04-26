import SwiftUI

/// Sheet that lets the user pick a background color and icon for a folder.
struct FolderAppearancePicker: View {
    @EnvironmentObject var appState: AppState
    let folderURL: URL
    let onDismiss: () -> Void

    @State private var selectedColorKey: String?
    @State private var selectedIconKey: String?

    // 4-column grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Appearance")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)
                    Text(folderURL.lastPathComponent)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                Spacer()
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: Color section
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Color", systemImage: "paintpalette")

                        LazyVGrid(columns: columns, spacing: 10) {
                            // "None" swatch
                            colorSwatch(key: nil, color: SynapseTheme.row)

                            ForEach(FolderColor.palette) { fc in
                                colorSwatch(key: fc.id, color: fc.color)
                            }
                        }
                    }

                    Divider().opacity(0.4)

                    // MARK: Icon section
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Icon", systemImage: "square.grid.3x3")

                        LazyVGrid(columns: columns, spacing: 10) {
                            // "None" icon swatch
                            iconSwatch(key: nil, symbolName: "folder.fill")

                            ForEach(FolderIcon.set) { fi in
                                iconSwatch(key: fi.id, symbolName: fi.symbolName)
                            }
                        }
                    }

                    // MARK: Action buttons
                    HStack(spacing: 10) {
                        Button("Clear") {
                            appState.clearFolderAppearance(for: folderURL)
                            onDismiss()
                        }
                        .buttonStyle(OutlineButtonStyle())

                        Spacer()

                        Button("Apply") {
                            appState.setFolderAppearance(
                                FolderAppearance(
                                    relativePath: appState.relativePath(for: folderURL) ?? folderURL.lastPathComponent,
                                    colorKey: selectedColorKey,
                                    iconKey: selectedIconKey
                                ),
                                for: folderURL
                            )
                            onDismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .background(SynapseTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            let current = appState.folderAppearance(for: folderURL)
            selectedColorKey = current?.colorKey
            selectedIconKey  = current?.iconKey
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SynapseTheme.textMuted)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(SynapseTheme.textMuted)
        }
    }

    @ViewBuilder
    private func colorSwatch(key: String?, color: Color) -> some View {
        let isSelected = selectedColorKey == key
        Button {
            selectedColorKey = key
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(height: 36)

                if key == nil {
                    // "None" indicator
                    Image(systemName: "slash.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(SynapseTheme.textMuted.opacity(0.6))
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SynapseTheme.accent, lineWidth: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SynapseTheme.accent)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SynapseTheme.textMuted.opacity(0.15), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconSwatch(key: String?, symbolName: String) -> some View {
        let isSelected = selectedIconKey == key
        let bg: Color = isSelected ? SynapseTheme.accent.opacity(0.18) : SynapseTheme.row
        let fg: Color = isSelected ? SynapseTheme.accent : SynapseTheme.textMuted
        let strokeColor: Color = isSelected ? SynapseTheme.accent : SynapseTheme.textMuted.opacity(0.15)

        Button {
            selectedIconKey = key
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bg)
                    .frame(height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
                    }
                Image(systemName: symbolName)
                    .font(.system(size: key == nil ? 14 : 14))
                    .foregroundStyle(fg)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(SynapseTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(SynapseTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SynapseTheme.textMuted.opacity(0.3), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
