import SwiftUI
import SwiftTerm

struct LocalTerminalView: NSViewRepresentable {
    let workingDirectory: String
    let onBootCommand: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["SHELL"] = "/bin/zsh"
        env["PWD"] = workingDirectory
        let envArray = env.map { "\($0.key)=\($0.value)" }

        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-l"],
            environment: envArray,
            execName: "zsh"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let escaped = workingDirectory.replacingOccurrences(of: " ", with: "\\ ")

            // Use on-boot command if set, otherwise just cd to project
            let commandToRun: String
            if let customCommand = onBootCommand, !customCommand.isEmpty {
                commandToRun = "cd \(escaped) && \(customCommand)"
            } else {
                commandToRun = "cd \(escaped)"
            }

            terminal.send(txt: commandToRun + "\n")
        }
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

struct TerminalPaneView: View {
    @EnvironmentObject var appState: AppState

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
