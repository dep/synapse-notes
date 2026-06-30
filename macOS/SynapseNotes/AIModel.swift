import Foundation

/// The three Anthropic models the inline AI editor can use.
/// API IDs are the exact Anthropic model strings — no date suffixes.
enum AIModel: String, CaseIterable, Identifiable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }

    var apiID: String {
        switch self {
        case .haiku:  return "claude-haiku-4-5"
        case .sonnet: return "claude-sonnet-5"
        case .opus:   return "claude-opus-4-8"
        }
    }

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku 4.5"
        case .sonnet: return "Sonnet 5"
        case .opus:   return "Opus 4.8"
        }
    }

    /// The default model — a balance of speed and quality.
    static let `default`: AIModel = .sonnet

    /// Resolve from a stored API ID string, falling back to the default.
    init(apiID: String) {
        self = AIModel.allCases.first { $0.apiID == apiID } ?? .default
    }
}
