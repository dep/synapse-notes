import Foundation

/// Title shown in the Connections / related-links sidebar header.
enum RelatedLinksTitleText {
    static func title(selectedFile: URL?) -> String {
        selectedFile?.deletingPathExtension().lastPathComponent ?? "Related Notes"
    }
}
