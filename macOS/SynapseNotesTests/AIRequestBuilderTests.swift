import XCTest
@testable import Synapse

final class AIRequestBuilderTests: XCTestCase {
    private func userText(_ body: [String: Any]) -> String {
        let messages = body["messages"] as! [[String: Any]]
        return messages.first(where: { $0["role"] as? String == "user" })!["content"] as! String
    }

    func test_generate_includesModelStreamMaxTokensAndNote() {
        let body = AIRequestBuilder.build(
            mode: .generate,
            prompt: "write a haiku",
            noteText: "# My Note\nSome text",
            selection: nil,
            context: [],
            model: .opus
        )
        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["max_tokens"])
        XCTAssertTrue(userText(body).contains("write a haiku"))
        XCTAssertTrue(userText(body).contains("# My Note"))
    }

    func test_rewrite_includesSelectedText() {
        let body = AIRequestBuilder.build(
            mode: .rewrite,
            prompt: "make it concise",
            noteText: "Full note body",
            selection: "The quick brown fox jumped.",
            context: [],
            model: .sonnet
        )
        XCTAssertTrue(userText(body).contains("make it concise"))
        XCTAssertTrue(userText(body).contains("The quick brown fox jumped."))
    }

    func test_contextBlocks_areLabeledByName() {
        let blocks = [AIContextResolver.Block(name: "Spec", body: "spec contents")]
        let body = AIRequestBuilder.build(
            mode: .generate, prompt: "p", noteText: "n",
            selection: nil, context: blocks, model: .haiku
        )
        let text = userText(body)
        XCTAssertTrue(text.contains("Spec"))
        XCTAssertTrue(text.contains("spec contents"))
    }

    func test_hasSystemPrompt() {
        let body = AIRequestBuilder.build(
            mode: .generate, prompt: "p", noteText: "n",
            selection: nil, context: [], model: .sonnet
        )
        let system = body["system"] as? String
        XCTAssertNotNil(system)
        XCTAssertFalse(system!.isEmpty)
    }

    func test_resultIsJSONSerializable() {
        let body = AIRequestBuilder.build(
            mode: .rewrite, prompt: "p", noteText: "n",
            selection: "s", context: [AIContextResolver.Block(name: "A", body: "b")],
            model: .opus
        )
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}
