import SwiftUI

struct FolderPickerView: View {
    @EnvironmentObject var appState: AppState
    @State private var isCloneSheetPresented = false

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack {
                Spacer(minLength: 0)

                VStack(spacing: 18) {
                    // App Icon Representation
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 8)

                    VStack(spacing: 10) {
                        Text("Synapse")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(SynapseTheme.textPrimary)

                        Text("A sleek markdown workspace with a focused editor, polished navigation, and a built-in terminal.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 360)
                    }

                    HStack(spacing: 8) {
                        TinyBadge(text: "Dark canvas")
                        TinyBadge(text: "Live markdown")
                        TinyBadge(text: "Terminal ready")
                    }

                    VStack(spacing: 10) {
                        Button(action: appState.pickFolder) {
                            Label("Open Folder…", systemImage: "folder.badge.plus")
                                .frame(width: 210)
                        }
                        .buttonStyle(PrimaryChromeButtonStyle())
                        .keyboardShortcut(.defaultAction)

                        Button(action: { isCloneSheetPresented = true }) {
                            Label("Clone Repository…", systemImage: "arrow.down.to.line")
                                .frame(width: 210)
                        }
                        .buttonStyle(ChromeButtonStyle())
                    }

                    Text("Open a local folder or clone a remote git repository.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 460)
                .synapsePanel(radius: 6)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $isCloneSheetPresented) {
            CloneRepositorySheet(isPresented: $isCloneSheetPresented)
                .environmentObject(appState)
        }
    }
}

private struct CloneRepositorySheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var remoteURL = ""
    @State private var destinationURL: URL? = nil
    @State private var isCloning = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone Repository")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository URL")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                TextField("https://github.com/user/repo.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCloning)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clone Into")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                HStack(spacing: 8) {
                    if let dest = destinationURL {
                        Text(dest.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SynapseTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No folder selected")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Choose…", action: pickDestination)
                        .buttonStyle(ChromeButtonStyle())
                        .disabled(isCloning)
                }
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SynapseTheme.border, lineWidth: 1)
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }

            if isCloning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                    Text("Cloning repository…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textSecondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .disabled(isCloning)

                Button("Clone", action: startClone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canClone || isCloning)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var canClone: Bool {
        !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && destinationURL != nil
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to clone the repository"
        panel.prompt = "Select"
        if panel.runModal() == .OK {
            destinationURL = panel.url
        }
    }

    private func startClone() {
        guard let destination = destinationURL else { return }
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        errorMessage = nil
        isCloning = true

        appState.cloneRepository(remoteURL: url, to: destination) { result in
            isCloning = false
            switch result {
            case .success:
                isPresented = false
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
