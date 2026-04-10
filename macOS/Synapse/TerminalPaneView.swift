import SwiftUI
import SwiftTerm

struct LocalTerminalView: NSViewRepresentable {
    let workingDirectory: String
    let onBootCommand: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        var env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["SHELL"] = shell
        env["PWD"] = workingDirectory
        let envArray = env.map { "\($0.key)=\($0.value)" }
        let shellName = URL(fileURLWithPath: shell).lastPathComponent

        terminal.startProcess(
            executable: shell,
            args: ["-l"],
            environment: envArray,
            execName: shellName
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let command = TerminalBootCommand.initialShellCommand(
                workingDirectory: workingDirectory,
                onBootCommand: onBootCommand
            )
            terminal.send(txt: command)

            // Re-trigger setFrameSize after the initial SwiftUI layout pass so
            // SwiftTerm's processSizeChange runs with the real bounds and sends
            // the correct TIOCSWINSZ to the PTY. Without this the terminal starts
            // with a zero-size frame and the cursor lands at column 0 (top-left)
            // until the user manually resizes the sidebar.
            let size = terminal.frame.size
            if size.width > 0 && size.height > 0 {
                terminal.setFrameSize(size)
            }
        }
        return terminal
    }

    /// Re-trigger setFrameSize whenever SwiftUI lays out the view (e.g. sidebar
    /// resize). SwiftTerm's setFrameSize override calls processSizeChange which
    /// recomputes cols/rows and sends TIOCSWINSZ to the PTY, keeping it in sync.
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        let size = nsView.frame.size
        guard size.width > 0 && size.height > 0 else { return }
        nsView.setFrameSize(size)
    }
}

struct TerminalPaneView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeEnv: ThemeEnvironment

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Terminal")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(SynapseTheme.textMuted)

                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(SynapseTheme.accent)
                        Text(appState.rootURL?.lastPathComponent ?? "Shell")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(SynapseTheme.textPrimary)
                    }

                    Text(appState.rootURL?.path ?? NSHomeDirectory())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                TinyBadge(text: "Live session")
            }

            Rectangle()
                .fill(SynapseTheme.divider)
                .frame(height: 1)

            LocalTerminalView(
                workingDirectory: appState.rootURL?.path ?? NSHomeDirectory(),
                onBootCommand: appState.settings.onBootCommand
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
