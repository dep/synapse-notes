import Foundation

/// Validation rules for the clone-repository sheet (folder picker welcome screen).
enum CloneRepositoryValidation {
    static func canClone(remoteURL: String, destinationURL: URL?) -> Bool {
        !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && destinationURL != nil
    }
}
