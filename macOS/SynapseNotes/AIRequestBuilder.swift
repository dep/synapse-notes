import Foundation

/// Builds the Anthropic /v1/messages request body for the inline editor.
/// Pure — returns a JSON-serializable dictionary.
enum AIRequestBuilder {
    enum Mode {
        case generate   // insert new text at the cursor
        case rewrite    // transform the selected text
    }

    static let maxTokens = 4096

    static func build(
        mode: Mode,
        prompt: String,
        noteText: String,
        selection: String?,
        context: [AIContextResolver.Block],
        model: AIModel
    ) -> [String: Any] {
        var user = ""

        if !context.isEmpty {
            user += "Reference notes:\n"
            for block in context {
                user += "--- @\(block.name) ---\n\(block.body)\n\n"
            }
        }

        user += "Current note:\n\"\"\"\n\(noteText)\n\"\"\"\n\n"

        switch mode {
        case .generate:
            user += "Task: \(prompt)\n\n"
            user += "Write the text to insert at the cursor. Output only the new text, no preamble, no markdown fences."
        case .rewrite:
            user += "Selected text:\n\"\"\"\n\(selection ?? "")\n\"\"\"\n\n"
            user += "Task: \(prompt)\n\n"
            user += "Rewrite the selected text accordingly. Output only the replacement text, no preamble, no markdown fences."
        }

        let system = """
        You are a writing assistant embedded in a Markdown note editor. \
        You produce text that drops directly into the user's note. \
        Match the surrounding tone and Markdown style. \
        Never wrap your answer in code fences or add commentary — output only the text the user asked for.
        """

        return [
            "model": model.apiID,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
    }
}
