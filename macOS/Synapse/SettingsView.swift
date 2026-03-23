import SwiftUI

// MARK: - Placeholder Extension

extension View {
    func placeholder(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> some View) -> some View {
        overlay(alignment: alignment) {
            if shouldShow {
                placeholder()
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage(kGitSSHAuthSock) private var sshAuthSock: String = ""
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: SettingsManager
    @State private var isDetecting = false
    @State private var detectError: String?
    @State private var templateVarsExpanded = false

    private let settingsFieldWidth: CGFloat = 440

    private func refreshEditorsForFontChange() {
        DispatchQueue.main.async {
            refreshAllEditorsForFontChange()
        }
    }

    var body: some View {
        Form {
            // MARK: - Editor Section
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Hide markdown toggle
                    Toggle("Hide markdown while editing", isOn: $settings.hideMarkdownWhileEditing)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    
                    Text("When enabled, markdown syntax is hidden as you type and content renders in real-time.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Body Font Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body Font")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        FontPicker(
                            selection: $settings.editorBodyFontFamily,
                            fonts: FontEnumerator.bodyFonts(),
                            defaultLabel: "System"
                        )
                        .frame(width: settingsFieldWidth, alignment: .leading)
                    }
                    
                    // Monospace Font Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Monospace Font")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        FontPicker(
                            selection: $settings.editorMonospaceFontFamily,
                            fonts: FontEnumerator.monospaceFonts(),
                            defaultLabel: "System Monospace"
                        )
                        .frame(width: settingsFieldWidth, alignment: .leading)
                    }
                    
                    // Font Size Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Font Size")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("", value: $settings.editorFontSize, format: .number)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            
                            Text("pt")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Line Height")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("", value: $settings.editorLineHeight, format: .number.precision(.fractionLength(1)))
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)

                            Text("x")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Font settings apply immediately and are saved with your vault.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Editor")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - On-Boot Command Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Terminal Command")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("", text: $settings.onBootCommand)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .placeholder(when: settings.onBootCommand.isEmpty) {
                            Text("npm run dev, claude, opencode…")
                                .foregroundStyle(.tertiary)
                        }

                    if !settings.onBootCommand.isEmpty {
                        Button("Clear") {
                            settings.onBootCommand = ""
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    }

                    Text("A command to run automatically when Synapse launches with a folder. Leave empty to do nothing.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("On-Boot Command")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Browser Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Startup URL")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("", text: $settings.browserStartupURL)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .placeholder(when: settings.browserStartupURL.isEmpty) {
                            Text("https://")
                                .foregroundStyle(.tertiary)
                        }

                    if !settings.browserStartupURL.isEmpty {
                        Button("Clear") {
                            settings.browserStartupURL = ""
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    }

                    Text("The mini-browser will open this URL on launch. Leave empty to restore the last visited URL.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Browser")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - File Extension Filter Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Show Files Matching")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("", text: $settings.fileExtensionFilter)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: settingsFieldWidth, alignment: .leading)
                        .placeholder(when: settings.fileExtensionFilter.isEmpty) {
                            Text("*")
                                .foregroundStyle(.tertiary)
                        }

                    HStack(spacing: 6) {
                        Button("*.md, *.txt") {
                            settings.fileExtensionFilter = "*.md, *.txt"
                        }
                        .font(.system(size: 11))

                        Button("* (all)") {
                            settings.fileExtensionFilter = "*"
                        }
                        .font(.system(size: 11))
                    }

                    Text("Hide Files, Folders Matching")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("", text: $settings.hiddenFileFolderFilter)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: settingsFieldWidth, alignment: .leading)
                        .placeholder(when: settings.hiddenFileFolderFilter.isEmpty) {
                            Text(".git, .synapse, .images")
                                .foregroundStyle(.tertiary)
                        }

                    if !settings.hiddenFileFolderFilter.isEmpty {
                        Button("Clear Hidden Rules") {
                            settings.hiddenFileFolderFilter = ""
                        }
                        .font(.system(size: 11))
                    }

                    Text("Filter which files appear in the sidebar. Use commas to list multiple patterns (e.g. *.md, *.txt) or * for all files. You can also hide matching files or folders with patterns like .git, .synapse, or .images. Changes apply immediately.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("File Browser")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Templates Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Templates Folder")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("", text: $settings.templatesDirectory)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: settingsFieldWidth, alignment: .leading)
                        .placeholder(when: settings.templatesDirectory.isEmpty) {
                            Text("templates")
                                .foregroundStyle(.tertiary)
                        }

                    Text("Markdown files inside this folder are offered as templates when you trigger New Note. Use a path relative to the open workspace.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { templateVarsExpanded.toggle() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: templateVarsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Template Variables")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if templateVarsExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach([
                                ("{{year}}", "4-digit year", "2026"),
                                ("{{month}}", "2-digit month, zero-padded", "03"),
                                ("{{day}}", "2-digit day, zero-padded", "12"),
                                ("{{hour}}", "12-hour format, zero-padded", "09"),
                                ("{{minute}}", "2-digit minute, zero-padded", "45"),
                                ("{{ampm}}", "AM or PM", "AM"),
                                ("{{cursor}}", "Initial cursor position", ""),
                            ], id: \.0) { variable, description, example in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(variable)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(SynapseTheme.accent)
                                        .frame(width: 100, alignment: .leading)
                                    Text(description + (example.isEmpty ? "" : " — e.g. \(example)"))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(SynapseTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Templates")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Daily Notes Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Daily Notes", isOn: $settings.dailyNotesEnabled)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    if settings.dailyNotesEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Daily Notes Folder")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField("", text: $settings.dailyNotesFolder)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                                .frame(width: settingsFieldWidth, alignment: .leading)
                                .placeholder(when: settings.dailyNotesFolder.isEmpty) {
                                    Text("daily")
                                        .foregroundStyle(.tertiary)
                                }

                            Text("Notes are stored here, relative to the open workspace. The folder is created automatically if it doesn't exist.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !settings.templatesDirectory.isEmpty {
                                let templates = appState.availableTemplates()
                                if !templates.isEmpty {
                                    Text("Template")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)

                                    Picker("", selection: $settings.dailyNotesTemplate) {
                                        Text("None").tag("")
                                        ForEach(templates, id: \.self) { url in
                                            Text(url.lastPathComponent).tag(url.lastPathComponent)
                                        }
                                    }
                                    .frame(width: settingsFieldWidth, alignment: .leading)
                                    .labelsHidden()

                                    Text("Applied to new daily notes. Template variables ({{year}}, {{month}}, {{day}}, {{hour}}, {{minute}}, {{ampm}}, {{cursor}}) are substituted on creation.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Toggle("Open today's note on startup", isOn: $settings.dailyNotesOpenOnStartup)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Daily Notes")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Git Sync Section (existing)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SSH Agent Socket Path")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(
                            "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock",
                            text: $sshAuthSock
                        )
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                        Button("Detect") {
                            detectFromShell()
                        }
                        .disabled(isDetecting)

                        if !sshAuthSock.isEmpty {
                            Button("Clear") {
                                sshAuthSock = ""
                                detectError = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    if isDetecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .progressViewStyle(.circular)
                            Text("Reading from shell environment…")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = detectError {
                        Text(err)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                    }

                    Text(helpText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Git Sync")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Auto-Save Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Stage changes on file save", isOn: $settings.autoSave)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text("Automatically stage git changes whenever a file is saved. Changes are committed when you push (Cmd+S, file switch, or quit).")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Auto-Save")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - Auto-Push Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Auto-push commits", isOn: $settings.autoPush)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text("When enabled, staged changes are committed and pushed when you press Cmd+S, switch files, or quit the app. Requires a remote repository.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Auto-Push")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            // MARK: - GitHub Gist Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Personal Access Token")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("ghp_...", text: $settings.githubPAT)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        if settings.hasGitHubPAT {
                            Button("Clear") {
                                settings.githubPAT = ""
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        }
                    }

                    Text("Used to publish notes to public GitHub Gists. The token needs the 'gist' scope.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        if let url = URL(string: "https://github.com/settings/tokens/new") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text("Create token on GitHub")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(SynapseTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            } header: {
                Text("GitHub Gist")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .onChange(of: settings.editorBodyFontFamily) { _ in
            refreshEditorsForFontChange()
        }
        .onChange(of: settings.editorMonospaceFontFamily) { _ in
            refreshEditorsForFontChange()
        }
        .onChange(of: settings.editorFontSize) { _ in
            refreshEditorsForFontChange()
        }
        .onChange(of: settings.editorLineHeight) { _ in
            refreshEditorsForFontChange()
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }

    private var helpText: String {
        if sshAuthSock.isEmpty {
            return "Optional. If git sync fails to trigger your SSH agent (e.g. 1Password Touch ID), click Detect or paste the output of \u{201C}echo $SSH_AUTH_SOCK\u{201D} from your terminal. When set, this path is used directly and the shell environment lookup is skipped."
        } else {
            return "Using the configured socket path. Remove it to fall back to automatic shell environment detection."
        }
    }

    // MARK: - Detect

    private func detectFromShell() {
        isDetecting = true
        detectError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let env = ProcessInfo.processInfo.environment
            let shell = env["SHELL"] ?? "/bin/zsh"
            let shellName = URL(fileURLWithPath: shell).lastPathComponent

            // Use the same interactive login shell approach as git invocations
            // so we get the same SSH_AUTH_SOCK that git would see.
            let args: [String] = shellName == "fish"
                ? ["-c", "printf '%s' $SSH_AUTH_SOCK"]
                : ["-i", "-l", "-c", "printf '%s' \"$SSH_AUTH_SOCK\""]

            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = args
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }

            guard (try? process.run()) != nil else {
                DispatchQueue.main.async {
                    self.detectError = "Could not launch shell. Try setting the path manually."
                    self.isDetecting = false
                }
                return
            }

            if semaphore.wait(timeout: .now() + 8) == .timedOut {
                process.terminate()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.detectError = "Shell timed out. Your .zshrc may be slow to load. Try setting the path manually."
                    self.isDetecting = false
                }
                return
            }

            let raw = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            // The output may contain startup noise from .zshrc. Find the last
            // line that looks like a socket path (absolute path ending in .sock).
            let detected = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { $0.hasPrefix("/") && $0.hasSuffix(".sock") }

            DispatchQueue.main.async {
                if let sock = detected {
                    self.sshAuthSock = sock
                } else if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Something was returned but didn't look like a socket path —
                    // let the user decide whether to use it.
                    self.sshAuthSock = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    self.detectError = "SSH_AUTH_SOCK is not set in your shell. Run \u{201C}echo $SSH_AUTH_SOCK\u{201D} in a terminal to find the value, then paste it here."
                }
                self.isDetecting = false
            }
        }
    }
}

// MARK: - Font Picker Component

struct FontPicker: View {
    @Binding var selection: String
    let fonts: [String]
    let defaultLabel: String
    
    var body: some View {
        Menu {
            // Default option at top
            Button(defaultLabel) {
                selection = defaultLabel == "System" ? "System" : "System Monospace"
            }
            
            Divider()
            
            // All fonts
            ForEach(fonts, id: \.self) { font in
                Button(font) {
                    selection = font
                }
            }
        } label: {
            HStack {
                Text(selection.isEmpty || selection == "System" || selection == "System Monospace" ? defaultLabel : selection)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 200)
    }
}

#Preview {
    SettingsView(settings: SettingsManager())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
