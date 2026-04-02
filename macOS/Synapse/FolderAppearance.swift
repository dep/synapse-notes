import SwiftUI

// MARK: - Pastel Color Palette

/// A named pastel color that looks good in both light and dark themes.
struct FolderColor: Identifiable, Equatable {
    let id: String          // key stored in settings
    let label: String
    let color: Color
}

extension FolderColor {
    /// The full predefined palette — 12 pastels.
    static let palette: [FolderColor] = [
        FolderColor(id: "rose",      label: "Rose",      color: Color(hex: "#F4ACAC")!),
        FolderColor(id: "peach",     label: "Peach",     color: Color(hex: "#F4C4A4")!),
        FolderColor(id: "honey",     label: "Honey",     color: Color(hex: "#F4DFA4")!),
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
    let label: String
    let symbolName: String  // SF Symbol name
}

extension FolderIcon {
    /// 20 outlined SF Symbol icons.
    static let set: [FolderIcon] = [
        FolderIcon(id: "star",        label: "Star",        symbolName: "star"),
        FolderIcon(id: "heart",       label: "Heart",       symbolName: "heart"),
        FolderIcon(id: "bookmark",    label: "Bookmark",    symbolName: "bookmark"),
        FolderIcon(id: "tag",         label: "Tag",         symbolName: "tag"),
        FolderIcon(id: "bolt",        label: "Bolt",        symbolName: "bolt"),
        FolderIcon(id: "flame",       label: "Flame",       symbolName: "flame"),
        FolderIcon(id: "leaf",        label: "Leaf",        symbolName: "leaf"),
        FolderIcon(id: "moon",        label: "Moon",        symbolName: "moon"),
        FolderIcon(id: "sun",         label: "Sun",         symbolName: "sun.max"),
        FolderIcon(id: "cloud",       label: "Cloud",       symbolName: "cloud"),
        FolderIcon(id: "drop",        label: "Drop",        symbolName: "drop"),
        FolderIcon(id: "atom",        label: "Atom",        symbolName: "atom"),
        FolderIcon(id: "briefcase",   label: "Briefcase",   symbolName: "briefcase"),
        FolderIcon(id: "camera",      label: "Camera",      symbolName: "camera"),
        FolderIcon(id: "music",       label: "Music",       symbolName: "music.note"),
        FolderIcon(id: "book",        label: "Book",        symbolName: "book.closed"),
        FolderIcon(id: "pencil",      label: "Pencil",      symbolName: "pencil"),
        FolderIcon(id: "lightbulb",   label: "Lightbulb",   symbolName: "lightbulb"),
        FolderIcon(id: "brain",       label: "Brain",       symbolName: "brain"),
        FolderIcon(id: "chart",       label: "Chart",       symbolName: "chart.bar"),
        FolderIcon(id: "robot",       label: "Robot",       symbolName: "cpu"),
        FolderIcon(id: "mobile",      label: "Mobile",      symbolName: "iphone"),
        FolderIcon(id: "people",      label: "People",      symbolName: "person.2"),
        FolderIcon(id: "person",      label: "Person",      symbolName: "person"),
        FolderIcon(id: "calendar",    label: "Calendar",    symbolName: "calendar"),
        FolderIcon(id: "wrench",      label: "Wrench",      symbolName: "wrench"),
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
