import SwiftUI

// MARK: - Pastel Color Palette

/// A named pastel color that looks good in both light and dark themes.
struct FolderColor: Identifiable, Equatable {
    let id: String          // key stored in settings
    let label: String       // display name
    let color: Color
}

extension FolderColor {
    /// The full predefined palette — 12 pastels.
    static let palette: [FolderColor] = [
        FolderColor(id: "rose",      label: "Rose",      color: Color(hex: "#F4ACAC")!),
        FolderColor(id: "peach",     label: "Peach",     color: Color(hex: "#F4C4A4")!),
        FolderColor(id: "honey",     label: "Honey",     color: Color(hex: "#F4DFA4")!),
        FolderColor(id: "amber",     label: "Amber",     color: Color(hex: "#F4DCA4")!),
        FolderColor(id: "sage",      label: "Sage",      color: Color(hex: "#B4E4B4")!),
        FolderColor(id: "mint",      label: "Mint",      color: Color(hex: "#B4F4D4")!),
        FolderColor(id: "teal",      label: "Teal",      color: Color(hex: "#A4D4E4")!),
        FolderColor(id: "sky",       label: "Sky",       color: Color(hex: "#A4C4F4")!),
        FolderColor(id: "lavender",  label: "Lavender",  color: Color(hex: "#C4B4F4")!),
        FolderColor(id: "violet",    label: "Violet",    color: Color(hex: "#E4B4F4")!),
        FolderColor(id: "blush",     label: "Blush",     color: Color(hex: "#F4B4D4")!),
        FolderColor(id: "sand",      label: "Sand",      color: Color(hex: "#E4D4B4")!),
    ]

    static func color(for id: String) -> FolderColor? {
        palette.first { $0.id == id }
    }
}

// MARK: - Folder Icon Set

/// A named SF Symbol outline icon for folders.
struct FolderIcon: Identifiable, Equatable {
    let id: String          // key stored in settings
    let symbolName: String  // SF Symbol name
}

extension FolderIcon {
    /// Outlined SF Symbols available for folder customization.
    static let set: [FolderIcon] = [
        FolderIcon(id: "star",        symbolName: "star"),
        FolderIcon(id: "heart",       symbolName: "heart"),
        FolderIcon(id: "bookmark",    symbolName: "bookmark"),
        FolderIcon(id: "tag",         symbolName: "tag"),
        FolderIcon(id: "bolt",        symbolName: "bolt"),
        FolderIcon(id: "flame",       symbolName: "flame"),
        FolderIcon(id: "leaf",        symbolName: "leaf"),
        FolderIcon(id: "moon",        symbolName: "moon"),
        FolderIcon(id: "sun",         symbolName: "sun.max"),
        FolderIcon(id: "cloud",       symbolName: "cloud"),
        FolderIcon(id: "drop",        symbolName: "drop"),
        FolderIcon(id: "atom",        symbolName: "atom"),
        FolderIcon(id: "briefcase",   symbolName: "briefcase"),
        FolderIcon(id: "camera",      symbolName: "camera"),
        FolderIcon(id: "music",       symbolName: "music.note"),
        FolderIcon(id: "book",        symbolName: "book.closed"),
        FolderIcon(id: "pencil",      symbolName: "pencil"),
        FolderIcon(id: "lightbulb",   symbolName: "lightbulb"),
        FolderIcon(id: "brain",       symbolName: "brain"),
        FolderIcon(id: "chart",       symbolName: "chart.bar"),
        FolderIcon(id: "robot",       symbolName: "cpu"),
        FolderIcon(id: "mobile",      symbolName: "iphone"),
        FolderIcon(id: "people",      symbolName: "person.2"),
        FolderIcon(id: "person",      symbolName: "person"),
        FolderIcon(id: "calendar",    symbolName: "calendar"),
        FolderIcon(id: "chat",        symbolName: "bubble.left"),
        FolderIcon(id: "wrench",      symbolName: "wrench"),
    ]

    static func icon(for id: String) -> FolderIcon? {
        set.first { $0.id == id }
    }
}

// MARK: - Folder Appearance Model

/// Per-folder color + icon customization, stored relative to vault root for portability.
struct FolderAppearance: Codable, Equatable, Identifiable {
    var id: String { relativePath }
    /// Path relative to vault root (e.g. "Projects/Work").
    let relativePath: String
    /// Key into `FolderColor.palette`, nil means default accent color.
    var colorKey: String?
    /// Key into `FolderIcon.set`, nil means default folder icon.
    var iconKey: String?

    var resolvedColor: Color? {
        guard let key = colorKey else { return nil }
        return FolderColor.color(for: key)?.color
    }

    var resolvedSymbolName: String? {
        guard let key = iconKey else { return nil }
        return FolderIcon.icon(for: key)?.symbolName
    }
}
