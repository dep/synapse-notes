import SwiftUI

/// Displays notes created or modified on a specific date.
/// Shows two sections: Created and Modified, each sorted by date descending.
struct DatePageView: View {
    @EnvironmentObject var appState: AppState
    let date: Date

    private let calendar = Calendar.current

    private var createdNotes: [URL] {
        appState.notesCreatedOnDate(date)
    }

    private var modifiedNotes: [URL] {
        appState.notesModifiedOnDate(date)
    }

    /// Returns the URL for the daily note if it exists, nil otherwise
    private var dailyNoteURL: URL? {
        appState.dailyNoteURL(for: date)
    }

    private var dateTitle: String {
        DatePageFormatting.isoTitle(for: date)
    }

    private var dateSubtitle: String {
        DatePageFormatting.mediumSubtitle(for: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundStyle(SynapseTheme.accent)
                            Text(dateTitle)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(SynapseTheme.textPrimary)
                        }

                        Text(dateSubtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }

                    Spacer()

                    // Daily Note Button (only shown if daily note exists)
                    if let dailyURL = dailyNoteURL {
                        Button(action: {
                            appState.openFile(dailyURL)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Open Daily Note")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(SynapseTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SynapseTheme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(SynapseTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Open daily note for this date")
                    }

                    Button(action: {
                        if let index = appState.activeTabIndex {
                            appState.closeTab(at: index)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SynapseTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(SynapseTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(SynapseTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close date view")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(SynapseTheme.panel)

            Rectangle()
                .fill(SynapseTheme.border)
                .frame(height: 1)

            // Content
            if createdNotes.isEmpty && modifiedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No notes")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)
                    Text("No notes were created or modified on this date.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Created section
                        if !createdNotes.isEmpty {
                            SectionHeader(
                                title: "Created",
                                count: createdNotes.count,
                                icon: "plus.circle.fill"
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(createdNotes, id: \.self) { url in
                                    DatePageNoteRow(url: url, appState: appState)
                                }
                            }
                        }

                        // Modified section
                        if !modifiedNotes.isEmpty {
                            SectionHeader(
                                title: "Modified",
                                count: modifiedNotes.count,
                                icon: "pencil.circle.fill"
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(modifiedNotes, id: \.self) { url in
                                    DatePageNoteRow(url: url, appState: appState)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SynapseTheme.editorShell)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(SynapseTheme.accent)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)

            Text("(\(count))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SynapseTheme.textMuted)

            Spacer()
        }
    }
}

// MARK: - Note Row

struct DatePageNoteRow: View {
    let url: URL
    @ObservedObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(SynapseTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                    .lineLimit(1)
                Text(appState.relativePath(for: url))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Text("⌘+Click for new tab")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SynapseTheme.row)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SynapseTheme.rowBorder, lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                    if isCommandPressed {
                        appState.openFileInNewTab(url)
                    } else {
                        appState.openFile(url)
                    }
                }
        )
    }
}
