# Inline AI Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user edit the current note with AI — an active-line ✨ generates streamed text at the cursor, a selection ✨ rewrites selected text as an inline accept/reject diff, with an Anthropic API key in the Keychain, a per-request model picker, and `@note` context autocomplete.

**Architecture:** Six focused units — `KeychainStore` (secure key), `AnthropicClient` (URLSession SSE transport), `AIContextResolver` + `AIRequestBuilder` (pure request assembly), `InlineAIController` (orchestrator/`ObservableObject`), and `InlineAIView` (the SwiftUI bar + ✨ overlay). They plug into the existing `LinkAwareTextView` overlay/selection lifecycle in `EditorView.swift` and the `SettingsManager`/`SettingsView` settings system. Pure units are unit-tested with TDD; AppKit overlay placement is verified by build-and-relaunch.

**Tech Stack:** Swift 5, AppKit + SwiftUI, `URLSession.bytes(for:)` async SSE, `Security.framework` Keychain, XCTest with `MockURLProtocol`. Built via XcodeGen (`xcodegen generate`) — new `.swift` files under `macOS/SynapseNotes/` and `macOS/SynapseNotesTests/` are auto-included. App target/scheme: **"Synapse Notes"**; test module: **`Synapse`**; test target: **`SynapseTests`**.

---

## Conventions used throughout this plan

All commands run from `/Users/dep/Sites/synapse-notes/macOS`.

**Regenerate the project after adding any new file** (XcodeGen globs the source dirs):
```bash
cd /Users/dep/Sites/synapse-notes/macOS && xcodegen generate
```

**Run a single test** (regenerate first if you added the test file this session):
```bash
cd /Users/dep/Sites/synapse-notes/macOS && xcodegen generate && \
xcodebuild test -project "Synapse Notes.xcodeproj" -scheme "Synapse Notes" \
  -destination "platform=macOS" \
  -only-testing:"SynapseTests/<TestClass>/<testMethod>" 2>&1 | tail -30
```

**Run a whole test class:** drop the `/<testMethod>` suffix.

**Build + relaunch the app** (required after any `.swift` change before asking for feedback — per `.agents/commands/RELOAD-MAC.md`):
```bash
pkill -9 "Synapse Notes" || true && sleep 1 && cd /Users/dep/Sites/synapse-notes/macOS && \
xcodegen generate && \
xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse Notes" -destination "platform=macOS" build && \
for app in ~/Library/Developer/Xcode/DerivedData/Synapse*-*/Build/Products/Debug/"Synapse Notes.app"; do [ -e "$app" ] && open "$app" && break; done
```

**No trailing whitespace** in any file (repo rule). **Test module import:** `@testable import Synapse`.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `SynapseNotes/KeychainStore.swift` | Get/set/delete the Anthropic API key in the Keychain. | Create |
| `SynapseNotes/AIModel.swift` | The 3-model enum: id strings + display names. | Create |
| `SynapseNotes/AIContextResolver.swift` | Resolve `@name` tokens → note contents, capped. Pure. | Create |
| `SynapseNotes/AIRequestBuilder.swift` | Build system + messages payload from prompt/note/selection/context. Pure. | Create |
| `SynapseNotes/AnthropicClient.swift` | URLSession SSE transport → `AsyncThrowingStream<String>`. | Create |
| `SynapseNotes/InlineAIController.swift` | Orchestrator `ObservableObject`: session state, streaming application, accept/reject/cancel. | Create |
| `SynapseNotes/InlineAIView.swift` | `InlineAIBarView` (SwiftUI) + `AISparkleButton` (NSControl). | Create |
| `SynapseNotes/SettingsManager.swift` | Add `aiDefaultModel` persisted in `GlobalConfig`. | Modify |
| `SynapseNotes/SettingsView.swift` | Add the "AI" settings `Section` (key field + model picker). | Modify |
| `SynapseNotes/EditorView.swift` | Host the ✨ overlay + bar; wire selection/caret + text mutation. | Modify |
| `SynapseNotesTests/*` | One test file per pure unit + controller. | Create |

Tasks are ordered so each builds on green tests from the prior one. Tasks 1–6 are pure/testable (TDD). Tasks 7–9 are AppKit/SwiftUI integration verified by build-and-relaunch.

---

### Task 1: AIModel enum

**Files:**
- Create: `macOS/SynapseNotes/AIModel.swift`
- Test: `macOS/SynapseNotesTests/AIModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/AIModelTests.swift
import XCTest
@testable import Synapse

final class AIModelTests: XCTestCase {
    func test_apiIDs_areExactAnthropicModelStrings() {
        XCTAssertEqual(AIModel.haiku.apiID, "claude-haiku-4-5")
        XCTAssertEqual(AIModel.sonnet.apiID, "claude-sonnet-5")
        XCTAssertEqual(AIModel.opus.apiID, "claude-opus-4-8")
    }

    func test_displayNames_areHumanReadable() {
        XCTAssertEqual(AIModel.haiku.displayName, "Haiku 4.5")
        XCTAssertEqual(AIModel.sonnet.displayName, "Sonnet 5")
        XCTAssertEqual(AIModel.opus.displayName, "Opus 4.8")
    }

    func test_initFromAPIID_roundTrips_andDefaultsToSonnetOnUnknown() {
        XCTAssertEqual(AIModel(apiID: "claude-opus-4-8"), .opus)
        XCTAssertEqual(AIModel(apiID: "garbage"), .sonnet)
    }

    func test_defaultModel_isSonnet() {
        XCTAssertEqual(AIModel.default, .sonnet)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:"SynapseTests/AIModelTests"` (see Conventions)
Expected: FAIL — `AIModel` is undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/AIModel.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/AIModel.swift SynapseNotesTests/AIModelTests.swift && \
git commit -m "feat(ai): add AIModel enum with exact Anthropic model IDs"
```

---

### Task 2: KeychainStore

**Files:**
- Create: `macOS/SynapseNotes/KeychainStore.swift`
- Test: `macOS/SynapseNotesTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/KeychainStoreTests.swift
import XCTest
@testable import Synapse

final class KeychainStoreTests: XCTestCase {
    // Use a dedicated test service so we never touch the real key.
    let store = KeychainStore(service: "com.SynapseNotes.tests.anthropic")

    override func setUp() {
        super.setUp()
        store.delete()
    }

    override func tearDown() {
        store.delete()
        super.tearDown()
    }

    func test_getBeforeSet_returnsNil() {
        XCTAssertNil(store.get())
    }

    func test_setThenGet_roundTrips() {
        store.set("sk-ant-secret")
        XCTAssertEqual(store.get(), "sk-ant-secret")
    }

    func test_setOverwrites_existingValue() {
        store.set("first")
        store.set("second")
        XCTAssertEqual(store.get(), "second")
    }

    func test_setEmptyString_deletesTheItem() {
        store.set("value")
        store.set("")
        XCTAssertNil(store.get())
    }

    func test_delete_removesValue() {
        store.set("value")
        store.delete()
        XCTAssertNil(store.get())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/KeychainStoreTests"`
Expected: FAIL — `KeychainStore` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/KeychainStore.swift
import Foundation
import Security

/// Securely stores a single secret (the Anthropic API key) in the macOS Keychain.
/// One instance == one (service, account) slot.
struct KeychainStore {
    let service: String
    let account: String

    init(service: String = "com.SynapseNotes.anthropic", account: String = "apiKey") {
        self.service = service
        self.account = account
    }

    /// Returns the stored secret, or nil if none is set.
    func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    /// Stores the secret, overwriting any existing value. An empty string deletes the item.
    func set(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { delete(); return }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Removes the stored secret if present.
    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (5 tests). (If the test host lacks Keychain entitlement and tests fail with `errSecMissingEntitlement`, re-run; the app target already runs with a generic-password-capable entitlement. If it persists, note it for the review checkpoint.)

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/KeychainStore.swift SynapseNotesTests/KeychainStoreTests.swift && \
git commit -m "feat(ai): add KeychainStore for the Anthropic API key"
```

---

### Task 3: AIContextResolver

**Files:**
- Create: `macOS/SynapseNotes/AIContextResolver.swift`
- Test: `macOS/SynapseNotesTests/AIContextResolverTests.swift`

This unit takes the user's prompt string plus the vault's note URLs, finds `@name` tokens, loads the matching note bodies (case-insensitive by stem, mirroring `EditorView.swift:3357` resolution), caps the total at ~100K chars, and reports missing refs + truncation. It reads file contents via an injected closure so tests don't touch disk.

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/AIContextResolverTests.swift
import XCTest
@testable import Synapse

final class AIContextResolverTests: XCTestCase {
    // Build a resolver whose "files" are in-memory: name -> body.
    private func makeResolver(_ files: [String: String], cap: Int = 100_000) -> AIContextResolver {
        let urls = files.keys.map { URL(fileURLWithPath: "/vault/\($0).md") }
        return AIContextResolver(
            allFiles: urls,
            charCap: cap,
            readContents: { url in files[url.deletingPathExtension().lastPathComponent] }
        )
    }

    func test_noAtTokens_returnsEmptyContextNoMissing() {
        let r = makeResolver(["Foo": "body"])
        let result = r.resolve(prompt: "summarize the note")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    func test_resolvesSingleAtToken_caseInsensitive() {
        let r = makeResolver(["Daily": "daily body"])
        let result = r.resolve(prompt: "use @daily please")
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].name, "Daily")
        XCTAssertEqual(result.blocks[0].body, "daily body")
        XCTAssertTrue(result.missing.isEmpty)
    }

    func test_missingRef_isReportedAndSkipped() {
        let r = makeResolver(["Foo": "x"])
        let result = r.resolve(prompt: "@nope and @Foo")
        XCTAssertEqual(result.blocks.map(\.name), ["Foo"])
        XCTAssertEqual(result.missing, ["nope"])
    }

    func test_overCap_truncatesAndFlags() {
        let big = String(repeating: "a", count: 60_000)
        let r = makeResolver(["One": big, "Two": big], cap: 100_000)
        let result = r.resolve(prompt: "@One @Two")
        XCTAssertTrue(result.truncated)
        let total = result.blocks.reduce(0) { $0 + $1.body.count }
        XCTAssertLessThanOrEqual(total, 100_000)
    }

    func test_duplicateRefs_resolvedOnce() {
        let r = makeResolver(["Foo": "x"])
        let result = r.resolve(prompt: "@Foo and again @foo")
        XCTAssertEqual(result.blocks.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/AIContextResolverTests"`
Expected: FAIL — `AIContextResolver` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/AIContextResolver.swift
import Foundation

/// Resolves `@name` tokens in a prompt into vault-note context blocks.
/// Pure: file contents are read through an injected closure.
struct AIContextResolver {
    struct Block: Equatable {
        let name: String   // the file stem actually matched
        let body: String
    }
    struct Result: Equatable {
        var blocks: [Block]
        var missing: [String]   // @tokens with no matching note
        var truncated: Bool
    }

    let allFiles: [URL]
    let charCap: Int
    let readContents: (URL) -> String?

    init(allFiles: [URL], charCap: Int = 100_000, readContents: @escaping (URL) -> String?) {
        self.allFiles = allFiles
        self.charCap = charCap
        self.readContents = readContents
    }

    /// Matches `@token` where token is letters/digits/_/-/space-free path-ish chars.
    private static let tokenRegex = try! NSRegularExpression(pattern: "@([\\w./-]+)")

    func resolve(prompt: String) -> Result {
        let ns = prompt as NSString
        let matches = Self.tokenRegex.matches(in: prompt, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var blocks: [Block] = []
        var missing: [String] = []
        var truncated = false
        var used = 0

        for match in matches {
            let token = ns.substring(with: match.range(at: 1))
            let key = token.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let url = allFiles.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == key
            }), let body = readContents(url) else {
                missing.append(token)
                continue
            }

            let name = url.deletingPathExtension().lastPathComponent
            let remaining = charCap - used
            if body.count > remaining {
                truncated = true
                if remaining > 0 {
                    blocks.append(Block(name: name, body: String(body.prefix(remaining))))
                    used = charCap
                }
                break
            }
            blocks.append(Block(name: name, body: body))
            used += body.count
        }

        return Result(blocks: blocks, missing: missing, truncated: truncated)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/AIContextResolver.swift SynapseNotesTests/AIContextResolverTests.swift && \
git commit -m "feat(ai): add AIContextResolver for @note context"
```

---

### Task 4: AIRequestBuilder

**Files:**
- Create: `macOS/SynapseNotes/AIRequestBuilder.swift`
- Test: `macOS/SynapseNotesTests/AIRequestBuilderTests.swift`

Pure assembly of the Anthropic request body (as a `[String: Any]` JSON dictionary, ready for `JSONSerialization`). Two modes: `.generate` (insert at cursor) and `.rewrite` (transform selection). Includes the full current note + resolved context blocks.

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/AIRequestBuilderTests.swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/AIRequestBuilderTests"`
Expected: FAIL — `AIRequestBuilder` / `AIRequestBuilder.Mode` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/AIRequestBuilder.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/AIRequestBuilder.swift SynapseNotesTests/AIRequestBuilderTests.swift && \
git commit -m "feat(ai): add AIRequestBuilder for generate/rewrite payloads"
```

---

### Task 5: AnthropicClient (SSE transport)

**Files:**
- Create: `macOS/SynapseNotes/AnthropicClient.swift`
- Test: `macOS/SynapseNotesTests/AnthropicClientTests.swift`

Streams `/v1/messages` SSE and emits text deltas. The `URLSession` is injectable (defaults to `.shared`), mirroring `GistPublisher`. Tests feed canned SSE bytes via a `MockURLProtocol` (adapted from `GistPublisherHTTPTests.swift`).

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/AnthropicClientTests.swift
import XCTest
@testable import Synapse

private final class MockSSEURLProtocol: URLProtocol {
    static var responseStatus: Int = 200
    static var bodyData: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: MockSSEURLProtocol.responseStatus,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockSSEURLProtocol.bodyData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AnthropicClientTests: XCTestCase {
    private func makeClient() -> AnthropicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        return AnthropicClient(apiKey: "sk-test", urlSession: URLSession(configuration: config))
    }

    private func sse(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").appending("\n").utf8)
    }

    override func tearDown() {
        MockSSEURLProtocol.responseStatus = 200
        MockSSEURLProtocol.bodyData = Data()
        super.tearDown()
    }

    func test_streamsTextDeltasInOrder() async throws {
        MockSSEURLProtocol.responseStatus = 200
        MockSSEURLProtocol.bodyData = sse([
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":", world"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let client = makeClient()
        var collected = ""
        for try await delta in client.stream(body: ["model": "claude-sonnet-5"]) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello, world")
    }

    func test_ignoresNonDeltaEvents() async throws {
        MockSSEURLProtocol.bodyData = sse([
            #"data: {"type":"message_start","message":{}}"#,
            #"data: {"type":"content_block_start","index":0}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"X"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let client = makeClient()
        var collected = ""
        for try await delta in client.stream(body: [:]) { collected += delta }
        XCTAssertEqual(collected, "X")
    }

    func test_401_throwsInvalidKey() async {
        MockSSEURLProtocol.responseStatus = 401
        MockSSEURLProtocol.bodyData = Data()
        let client = makeClient()
        do {
            for try await _ in client.stream(body: [:]) {}
            XCTFail("expected throw")
        } catch let error as AnthropicClient.ClientError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_500_throwsServerError() async {
        MockSSEURLProtocol.responseStatus = 500
        let client = makeClient()
        do {
            for try await _ in client.stream(body: [:]) {}
            XCTFail("expected throw")
        } catch let error as AnthropicClient.ClientError {
            XCTAssertEqual(error, .server(status: 500))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/AnthropicClientTests"`
Expected: FAIL — `AnthropicClient` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/AnthropicClient.swift
import Foundation

/// Streams text deltas from the Anthropic /v1/messages SSE endpoint.
/// The URLSession is injectable for testing; defaults to .shared.
struct AnthropicClient {
    enum ClientError: Error, Equatable {
        case invalidKey
        case server(status: Int)
        case badResponse
    }

    let apiKey: String
    var urlSession: URLSession = .shared

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Streams `text_delta` strings. The async sequence finishes on `message_stop`
    /// or end of stream, and throws `ClientError` on a non-2xx status.
    func stream(body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.badResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        // Drain so the connection closes cleanly.
                        for try await _ in bytes.lines {}
                        if http.statusCode == 401 { throw ClientError.invalidKey }
                        throw ClientError.server(status: http.statusCode)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if json["type"] as? String == "message_stop" { break }
                        if json["type"] as? String == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests). Note: the mock delivers the full body at once; `bytes.lines` still splits it into lines, so the assertions hold.

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/AnthropicClient.swift SynapseNotesTests/AnthropicClientTests.swift && \
git commit -m "feat(ai): add AnthropicClient SSE streaming transport"
```

---

### Task 6: InlineAIController (orchestrator, accept/reject logic)

**Files:**
- Create: `macOS/SynapseNotes/InlineAIController.swift`
- Test: `macOS/SynapseNotesTests/InlineAIControllerTests.swift`

This holds the streaming state machine and the rewrite accept/reject logic, expressed against an `NSTextStorage` so it's testable without a live text view. It does **not** own the SSE call directly in the tested surface — the test drives `appendDelta`/`accept`/`reject` to exercise the diff logic. (The view layer in Task 7 connects `AnthropicClient` deltas to `appendDelta`.)

- [ ] **Step 1: Write the failing test**

```swift
// macOS/SynapseNotesTests/InlineAIControllerTests.swift
import XCTest
import AppKit
@testable import Synapse

final class InlineAIControllerTests: XCTestCase {
    private func makeStorage(_ s: String) -> NSTextStorage {
        NSTextStorage(string: s)
    }

    // MARK: generate mode

    func test_generate_appendDeltas_insertsAtCursor() {
        let storage = makeStorage("Hello  world")
        let c = InlineAIController()
        c.beginGenerate(in: storage, at: 6)   // between the two spaces
        c.appendDelta("brave new")
        c.appendDelta(" ")
        XCTAssertEqual(storage.string, "Hello brave new  world")
    }

    func test_generate_cancel_keepsPartialText() {
        let storage = makeStorage("ab")
        let c = InlineAIController()
        c.beginGenerate(in: storage, at: 2)
        c.appendDelta("XY")
        c.cancel()
        XCTAssertEqual(storage.string, "abXY")
    }

    // MARK: rewrite mode

    func test_rewrite_appendDeltas_keepOriginalUntilAccept() {
        let storage = makeStorage("The fox.")
        let c = InlineAIController()
        // select "The fox." == range 0..<8
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 8))
        c.appendDelta("A fox.")
        // original still present; new text appended after it
        XCTAssertTrue(storage.string.contains("The fox."))
        XCTAssertTrue(storage.string.contains("A fox."))
    }

    func test_rewrite_accept_replacesOriginalWithNew() {
        let storage = makeStorage("The fox.")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 8))
        c.appendDelta("A fox.")
        c.accept()
        XCTAssertEqual(storage.string, "A fox.")
    }

    func test_rewrite_reject_restoresOriginalOnly() {
        let storage = makeStorage("The fox.")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 8))
        c.appendDelta("A fox.")
        c.reject()
        XCTAssertEqual(storage.string, "The fox.")
    }

    func test_rewrite_cancelMidStream_thenAccept_usesPartial() {
        let storage = makeStorage("The fox.")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 8))
        c.appendDelta("A ")
        c.cancel()      // streaming stopped; still in pending-accept state
        c.accept()
        XCTAssertEqual(storage.string, "A ")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/InlineAIControllerTests"`
Expected: FAIL — `InlineAIController` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// macOS/SynapseNotes/InlineAIController.swift
import AppKit
import Combine

/// Orchestrates an inline AI editing session against an NSTextStorage.
///
/// Generate mode: streamed deltas are inserted at the cursor (plain text).
/// Rewrite mode: the original selection is kept; new text streams in after it.
/// On `accept`, the original is deleted and the new text remains. On `reject`,
/// the new text is removed and the original stays. Diff *coloring* is applied
/// by the view layer (Task 7) via the published `diffRange`s; this controller
/// owns only the text mutations so the logic stays unit-testable.
final class InlineAIController: ObservableObject {
    enum Mode: Equatable { case idle, generate, rewrite }

    @Published private(set) var mode: Mode = .idle
    /// Range of the original (struck-through) text during a rewrite; nil otherwise.
    @Published private(set) var originalRange: NSRange?
    /// Range of the streamed new text (generate: the inserted text; rewrite: the green text).
    @Published private(set) var newRange: NSRange?

    private weak var storage: NSTextStorage?

    // MARK: Generate

    func beginGenerate(in storage: NSTextStorage, at location: Int) {
        self.storage = storage
        mode = .generate
        originalRange = nil
        newRange = NSRange(location: location, length: 0)
    }

    // MARK: Rewrite

    func beginRewrite(in storage: NSTextStorage, selection: NSRange) {
        self.storage = storage
        mode = .rewrite
        originalRange = selection
        // New text starts immediately after the original selection.
        newRange = NSRange(location: selection.location + selection.length, length: 0)
    }

    // MARK: Streaming

    /// Appends a streamed text delta at the end of the current `newRange`.
    func appendDelta(_ text: String) {
        guard let storage, var nr = newRange, mode != .idle else { return }
        let insertAt = nr.location + nr.length
        storage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: text)
        nr.length += (text as NSString).length
        newRange = nr
    }

    /// Stops streaming but stays in the pending state (rewrite still awaits accept/reject).
    func cancel() {
        if mode == .generate { finishGenerate() }
        // rewrite: remain pending so the user can accept/reject the partial.
    }

    // MARK: Resolution

    /// Generate has no diff — once done, there's nothing to accept; just clear state.
    private func finishGenerate() {
        mode = .idle
        originalRange = nil
        newRange = nil
    }

    /// Rewrite accept: delete the original, keep the new text.
    func accept() {
        guard mode == .rewrite, let storage, let orig = originalRange else {
            finishGenerate(); return
        }
        // Delete the original range; the new text sits right after it, so deleting
        // the original shifts the new text left into the original's place.
        storage.replaceCharacters(in: orig, with: "")
        mode = .idle
        originalRange = nil
        newRange = nil
    }

    /// Rewrite reject: delete the streamed new text, restore the original.
    func reject() {
        guard mode == .rewrite, let storage, let nr = newRange else {
            finishGenerate(); return
        }
        storage.replaceCharacters(in: nr, with: "")
        mode = .idle
        originalRange = nil
        newRange = nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/InlineAIController.swift SynapseNotesTests/InlineAIControllerTests.swift && \
git commit -m "feat(ai): add InlineAIController streaming + accept/reject logic"
```

---

### Task 7: Settings — `aiDefaultModel` persistence + AI settings UI

**Files:**
- Modify: `macOS/SynapseNotes/SettingsManager.swift`
- Modify: `macOS/SynapseNotes/SettingsView.swift`
- Test: `macOS/SynapseNotesTests/SettingsManagerAIModelTests.swift`

`aiDefaultModel` is a machine-local preference → lives in `GlobalConfig`, threaded through exactly like `githubPAT`. The API key is **not** persisted here — only in `KeychainStore`.

- [ ] **Step 1: Write the failing test** (round-trips `aiDefaultModel` through save/reload, mirroring `SettingsManagerGitHubPATTests`)

```swift
// macOS/SynapseNotesTests/SettingsManagerAIModelTests.swift
import XCTest
@testable import Synapse

final class SettingsManagerAIModelTests: XCTestCase {
    private var tempDir: URL!
    private var globalPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        globalPath = tempDir.appendingPathComponent("global.yml").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_default_isSonnetAPIID() {
        let mgr = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        XCTAssertEqual(mgr.aiDefaultModel, "claude-sonnet-5")
    }

    func test_aiDefaultModel_persistsAcrossReload() {
        let mgr = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        mgr.aiDefaultModel = "claude-opus-4-8"
        // Force a reload from disk into a fresh manager.
        let reloaded = SettingsManager(vaultRoot: tempDir, globalConfigPath: globalPath)
        XCTAssertEqual(reloaded.aiDefaultModel, "claude-opus-4-8")
    }
}
```

> Note: confirm the `SettingsManager(vaultRoot:globalConfigPath:)` initializer signature against `SettingsManager.swift` (the full `init` around line 718+); if the designated init differs, mirror the exact form used in `SettingsManagerGitHubPATTests.swift`.

- [ ] **Step 2: Run test to verify it fails**

Run: `... -only-testing:"SynapseTests/SettingsManagerAIModelTests"`
Expected: FAIL — `aiDefaultModel` undefined.

- [ ] **Step 3a: Add the published property** — in `SettingsManager.swift`, after the `githubPAT` property (around line 274-276), add:

```swift
    /// Default Anthropic model for inline AI editing (machine-local).
    @Published var aiDefaultModel: String {
        didSet { save() }
    }
```

- [ ] **Step 3b: Add the `GlobalConfig` field + inits** — in the `GlobalConfig` struct (line 669):

Add the stored property after `vaultPath`:
```swift
        var aiDefaultModel: String?
```
Add a parameter to the memberwise `init` (after `lastNoteFolderPerVault`) and assign it:
```swift
            aiDefaultModel: String? = nil
```
```swift
            self.aiDefaultModel = aiDefaultModel
```
Add to `init(from:)`:
```swift
            aiDefaultModel = try container.decodeIfPresent(String.self, forKey: .aiDefaultModel)
```

- [ ] **Step 3c: Initialize the property in every initializer** — wherever `githubPAT = ""` is set in init (lines ~748, ~806) and where defaults are applied, add alongside:

```swift
        aiDefaultModel = "claude-sonnet-5"
```

- [ ] **Step 3d: Apply on load** — in `applyGlobalConfig(_:)` (line 1006), after the `githubPAT` line (1007), add:

```swift
        aiDefaultModel = globalConfig?.aiDefaultModel ?? "claude-sonnet-5"
```

- [ ] **Step 3e: Persist on save** — in BOTH `writeGlobalOnly()` (line 1258) and `writeVault()`'s `GlobalConfig(...)` (line 1377), add the argument after `lastNoteFolderPerVault:`:

```swift
                aiDefaultModel: aiDefaultModel
```

> Also add `aiDefaultModel` to the legacy `LegacyFile` struct + `writeLegacy()` (lines 1276-1339) and `applyLegacyConfig` if the legacy path sets `githubPAT` — search for every `githubPAT` assignment and mirror it. Run `grep -n githubPAT SettingsManager.swift` and ensure `aiDefaultModel` appears at each corresponding site.

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5a: Add the AI settings Section UI** — in `SettingsView.swift`, locate the GitHub Gist `Section` (search for the `SecureField` bound to `settings.githubPAT`) and add a new `Section` after it:

```swift
                Section(header: Text("AI")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anthropic API Key")
                            .font(.headline)
                        SecureField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: anthropicKey) { newValue in
                                KeychainStore().set(newValue)
                            }
                        Text("Stored securely in your macOS Keychain. Used for inline AI editing (✨).")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Text("Default Model")
                            .font(.headline)
                        Picker("Default Model", selection: Binding(
                            get: { AIModel(apiID: settings.aiDefaultModel) },
                            set: { settings.aiDefaultModel = $0.apiID }
                        )) {
                            ForEach(AIModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
```

- [ ] **Step 5b: Add the backing state** — near the top of the `SettingsView` struct body, alongside the other `@State`/`@ObservedObject` declarations, add:

```swift
    @State private var anthropicKey: String = KeychainStore().get() ?? ""
```

- [ ] **Step 6: Build + relaunch and verify Settings**

Run the build+relaunch command (see Conventions). Open Settings → AI section. Type a key, quit, reopen Settings — the key should persist (Keychain). Switch the model picker, quit, reopen — selection persists (YAML).

- [ ] **Step 7: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/SettingsManager.swift SynapseNotes/SettingsView.swift SynapseNotesTests/SettingsManagerAIModelTests.swift && \
git commit -m "feat(ai): add Anthropic key (Keychain) + default model to Settings"
```

---

### Task 8: InlineAIView — the bar + ✨ button + `@` autocomplete

**Files:**
- Create: `macOS/SynapseNotes/InlineAIView.swift`

This is SwiftUI/AppKit UI verified by build-and-relaunch (no unit test for layout). It contains:
- `AISparkleButton: NSControl` — the ✨ overlay (mirrors `CollapsibleToggleButton` in `EditorView.swift:1135`).
- `InlineAIBarView: View` — prompt `TextField`, model `Picker`, Stop/Accept/Reject buttons, an inline error line, and an `@`-autocomplete suggestion list. Hosted via `NSHostingView`.
- A small view model `InlineAIBarModel: ObservableObject` holding prompt text, model, streaming/error state, and the `@`-suggestions, computed with `commandPaletteScoreByFilename` (`CommandPaletteView.swift:15`).

- [ ] **Step 1: Create the file with the button + bar**

```swift
// macOS/SynapseNotes/InlineAIView.swift
import SwiftUI
import AppKit

/// The clickable ✨ overlay placed at the active line's end or past a selection.
/// Mirrors CollapsibleToggleButton's target/action overlay pattern.
final class AISparkleButton: NSControl {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "Ask AI"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let s = NSAttributedString(string: "✨", attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

/// Whether the bar opens to generate at the cursor or rewrite a selection.
enum InlineAIBarMode { case generate, rewrite }

/// View model backing the inline AI bar.
final class InlineAIBarModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var model: AIModel
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var awaitingAcceptReject: Bool = false   // rewrite finished, awaiting decision
    @Published var atSuggestions: [String] = []         // file stems matching the active @token

    let mode: InlineAIBarMode
    /// Vault file stems, for @-autocomplete.
    var allFileStems: [String] = []

    // Callbacks wired by the host (Task 9).
    var onSubmit: ((String, AIModel) -> Void)?
    var onStop: (() -> Void)?
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    var onCancel: (() -> Void)?   // Esc with nothing pending → close the bar

    init(mode: InlineAIBarMode, model: AIModel) {
        self.mode = mode
        self.model = model
    }

    /// Recompute @-autocomplete suggestions for the current prompt.
    func updateSuggestions() {
        guard let token = activeAtToken(in: prompt), !token.isEmpty else {
            atSuggestions = []
            return
        }
        // Score stems by the same algorithm wiki-link autocomplete uses.
        atSuggestions = allFileStems
            .map { ($0, commandPaletteScoreByFilename(query: token, filename: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0.0 }
    }

    /// Extracts the in-progress @token at the end of the prompt, if any.
    private func activeAtToken(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let after = text[text.index(after: atIndex)...]
        // No spaces inside a token; if there's a space after @, it's complete.
        if after.contains(" ") { return nil }
        return String(after)
    }

    /// Replace the active @token with the chosen stem.
    func applySuggestion(_ stem: String) {
        guard let atIndex = prompt.lastIndex(of: "@") else { return }
        prompt = String(prompt[..<atIndex]) + "@" + stem + " "
        atSuggestions = []
    }
}

struct InlineAIBarView: View {
    @ObservedObject var model: InlineAIBarModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("✨")
                TextField(model.mode == .generate ? "Ask AI to write…" : "Ask AI to edit…",
                          text: $model.prompt)
                    .textFieldStyle(.plain)
                    .focused($promptFocused)
                    .onChange(of: model.prompt) { _ in model.updateSuggestions() }
                    .onSubmit { submit() }

                Picker("", selection: $model.model) {
                    ForEach(AIModel.allCases) { m in Text(m.displayName).tag(m) }
                }
                .labelsHidden()
                .frame(width: 110)

                if model.isStreaming {
                    Button("Stop") { model.onStop?() }
                } else if model.awaitingAcceptReject {
                    Button("Accept") { model.onAccept?() }.keyboardShortcut(.return, modifiers: [])
                    Button("Reject") { model.onReject?() }.keyboardShortcut(.escape, modifiers: [])
                    Button("Retry") { submit() }
                } else {
                    Button("Generate") { submit() }.disabled(model.prompt.isEmpty)
                }
            }

            if let err = model.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
            }

            if !model.atSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.atSuggestions, id: \.self) { stem in
                        Button {
                            model.applySuggestion(stem)
                            promptFocused = true
                        } label: {
                            HStack { Text("@\(stem)"); Spacer() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
        .cornerRadius(8)
        .onAppear { promptFocused = true }
    }

    private func submit() {
        guard !model.prompt.isEmpty else { return }
        model.onSubmit?(model.prompt, model.model)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/dep/Sites/synapse-notes/macOS && xcodegen generate && \
xcodebuild -project "Synapse Notes.xcodeproj" -scheme "Synapse Notes" -destination "platform=macOS" build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED. (If `commandPaletteScoreByFilename` has a different parameter label, fix the call to match `CommandPaletteView.swift:15`.)

- [ ] **Step 3: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/InlineAIView.swift && \
git commit -m "feat(ai): add inline AI bar view, ✨ button, and @ autocomplete"
```

---

### Task 9: Wire it into the editor

**Files:**
- Modify: `macOS/SynapseNotes/EditorView.swift`

Connect everything: position the ✨ on caret/selection change, open the bar on click, drive the controller from `AnthropicClient` deltas, apply diff coloring, and handle accept/reject/cancel. This is integration code verified by build-and-relaunch.

- [ ] **Step 1: Add an `InlineAIController` + overlay state to `LinkAwareTextView`**

In `LinkAwareTextView` (class at `EditorView.swift:2292`), add stored properties near the other overlay state (e.g. near `collapsibleToggleButtons` at line 2342):

```swift
    let inlineAIController = InlineAIController()
    private var aiSparkleButton: AISparkleButton?
    private var aiBarHostingView: NSHostingView<InlineAIBarView>?
    private var aiBarModel: InlineAIBarModel?
    private var aiStreamTask: Task<Void, Never>?
    /// Reference to AppState for vault files + API key, injected at setup.
    weak var aiAppState: AppState?
    var aiSettings: SettingsManager? { settings }   // `settings` already exists on this class
```

- [ ] **Step 2: Position the ✨ on layout/selection change**

Add a `refreshAISparkle()` method modeled on `refreshCollapsibleToggles()` (`EditorView.swift:2181`), and call it from the same places that refresh overlays AND from the selection-change path. To avoid the un-debounced caret-move cost documented in the typing-perf memory, this must be cheap (one glyph-rect lookup, reposition one reused button — no parsing):

```swift
    func refreshAISparkle() {
        guard let layoutManager, let textContainer else { return }
        let sel = selectedRange()

        // Choose anchor: end of selection if there is one, else end of caret's line.
        let anchorIndex: Int
        if sel.length > 0 {
            anchorIndex = sel.location + sel.length
        } else {
            let ns = string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            // End of line content (before the trailing newline if present).
            var end = lineRange.location + lineRange.length
            if end > lineRange.location,
               ns.substring(with: NSRange(location: end - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil {
                end -= 1
            }
            anchorIndex = end
        }

        let safe = max(0, min(anchorIndex, (string as NSString).length))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: max(0, safe - 1), length: safe > 0 ? 1 : 0), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let size: CGFloat = 18
        let frame = NSRect(x: rect.maxX + 4, y: rect.minY + (rect.height - size) / 2, width: size, height: size)

        let button: AISparkleButton
        if let existing = aiSparkleButton {
            button = existing
        } else {
            button = AISparkleButton(frame: frame)
            button.target = self
            button.action = #selector(aiSparkleTapped)
            addSubview(button)
            aiSparkleButton = button
        }
        button.frame = frame
        button.isHidden = (aiBarHostingView != nil)   // hide while the bar is open
    }
```

Call `refreshAISparkle()` at the end of `refreshCollapsibleToggles()` (so it runs on every overlay refresh) and at the end of the coordinator's `textViewDidChangeSelection` (`EditorView.swift:1061`) — but route the selection-change call through the SAME debounce the existing reveal re-hide uses (see `EditorView.swift:1061-1096`), not synchronously, to respect the typing-perf hot path.

- [ ] **Step 3: Open the bar on ✨ click**

```swift
    @objc private func aiSparkleTapped() {
        let sel = selectedRange()
        let mode: InlineAIBarMode = sel.length > 0 ? .rewrite : .generate
        presentAIBar(mode: mode, at: sel)
    }

    private func presentAIBar(mode: InlineAIBarMode, at sel: NSRange) {
        dismissAIBar()   // ensure single instance

        let defaultModel = AIModel(apiID: aiSettings?.aiDefaultModel ?? AIModel.default.apiID)
        let model = InlineAIBarModel(mode: mode, model: defaultModel)
        model.allFileStems = (aiAppState?.allFiles ?? []).map { $0.deletingPathExtension().lastPathComponent }

        model.onSubmit = { [weak self] prompt, chosen in self?.startAIStream(prompt: prompt, model: chosen, mode: mode, selection: sel) }
        model.onStop   = { [weak self] in self?.stopAIStream() }
        model.onAccept = { [weak self] in self?.acceptAI() }
        model.onReject = { [weak self] in self?.rejectAI() }
        model.onCancel = { [weak self] in self?.dismissAIBar() }
        aiBarModel = model

        let host = NSHostingView(rootView: InlineAIBarView(model: model))
        host.frame = aiBarFrame(below: sel)
        addSubview(host)
        aiBarHostingView = host
        refreshAISparkle()   // hides the sparkle while bar is open
    }

    private func aiBarFrame(below sel: NSRange) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let anchor = sel.length > 0 ? sel.location + sel.length : sel.location
        let safe = max(0, min(anchor, (string as NSString).length))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: safe, length: 0), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let width = min(bounds.width - 24, 520)
        return NSRect(x: 12, y: rect.maxY + 4, width: width, height: 80)
    }

    private func dismissAIBar() {
        aiStreamTask?.cancel(); aiStreamTask = nil
        aiBarHostingView?.removeFromSuperview(); aiBarHostingView = nil
        aiBarModel = nil
        refreshAISparkle()
    }
```

- [ ] **Step 4: Drive the controller from `AnthropicClient`**

```swift
    private func startAIStream(prompt: String, model: AIModel, mode: InlineAIBarMode, selection sel: NSRange) {
        guard let storage = textStorage else { return }
        guard let key = KeychainStore().get(), !key.isEmpty else {
            aiBarModel?.errorMessage = "Add your Anthropic API key in Settings →"
            return
        }

        // Resolve @-context.
        let files = aiAppState?.allFiles ?? []
        let resolver = AIContextResolver(allFiles: files, readContents: { try? String(contentsOf: $0, encoding: .utf8) })
        let resolved = resolver.resolve(prompt: prompt)

        // Begin the controller session.
        if mode == .generate {
            inlineAIController.beginGenerate(in: storage, at: sel.location)
        } else {
            inlineAIController.beginRewrite(in: storage, selection: sel)
        }

        let selectionText = mode == .rewrite ? (string as NSString).substring(with: sel) : nil
        let body = AIRequestBuilder.build(
            mode: mode == .generate ? .generate : .rewrite,
            prompt: prompt, noteText: string,
            selection: selectionText, context: resolved.blocks, model: model
        )

        aiBarModel?.isStreaming = true
        aiBarModel?.errorMessage = resolved.truncated ? "Context truncated to fit." : (resolved.missing.isEmpty ? nil : "\(resolved.missing.count) reference(s) not found.")

        let client = AnthropicClient(apiKey: key)
        aiStreamTask = Task { [weak self] in
            do {
                for try await delta in client.stream(body: body) {
                    await MainActor.run {
                        self?.inlineAIController.appendDelta(delta)
                        self?.applyAIDiffColors()
                        self?.didChangeText()
                    }
                }
                await MainActor.run { self?.finishAIStream(mode: mode) }
            } catch {
                await MainActor.run { self?.handleAIError(error) }
            }
        }
    }

    private func stopAIStream() {
        aiStreamTask?.cancel(); aiStreamTask = nil
        inlineAIController.cancel()
        finishAIStream(mode: aiBarModel?.mode ?? .generate)
    }

    private func finishAIStream(mode: InlineAIBarMode) {
        aiBarModel?.isStreaming = false
        if mode == .rewrite {
            aiBarModel?.awaitingAcceptReject = true   // wait for accept/reject
        } else {
            inlineAIController.cancel()                // generate: nothing to accept
            dismissAIBar()
        }
        applyAIDiffColors()
    }

    private func handleAIError(_ error: Error) {
        aiBarModel?.isStreaming = false
        if let e = error as? AnthropicClient.ClientError {
            switch e {
            case .invalidKey: aiBarModel?.errorMessage = "Invalid API key — check Settings."
            case .server(let s): aiBarModel?.errorMessage = "Server error (\(s)). Try again."
            case .badResponse: aiBarModel?.errorMessage = "Unexpected response. Try again."
            }
        } else {
            aiBarModel?.errorMessage = "Network error. Try again."
        }
        // Keep whatever streamed; if rewrite, allow accept/reject of the partial.
        if aiBarModel?.mode == .rewrite { aiBarModel?.awaitingAcceptReject = true }
    }

    private func acceptAI() {
        inlineAIController.accept()
        clearAIDiffColors()
        didChangeText()
        dismissAIBar()
    }

    private func rejectAI() {
        inlineAIController.reject()
        clearAIDiffColors()
        didChangeText()
        dismissAIBar()
    }
```

- [ ] **Step 5: Apply transient diff coloring**

Diff coloring is a transient overlay applied AFTER the styling pass and cleared on accept/reject — it must not be baked into the persistent styling (`applyPreviewStyling` is a pure hide pass; see the spec's implementation note). Use temporary attributes:

```swift
    private func applyAIDiffColors() {
        guard let storage = textStorage else { return }
        if let orig = inlineAIController.originalRange, orig.length > 0,
           NSMaxRange(orig) <= storage.length {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: orig)
            storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: orig)
        }
        if let nr = inlineAIController.newRange, nr.length > 0,
           NSMaxRange(nr) <= storage.length {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: nr)
        }
    }

    private func clearAIDiffColors() {
        // The next refreshEditorForCurrentDisplayMode pass restores correct styling;
        // remove the transient strike-through so it doesn't linger.
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.strikethroughStyle, range: full)
        refreshEditorForCurrentDisplayMode(self)
    }
```

- [ ] **Step 6: Inject `aiAppState`** — find where `RawEditor.makeNSView` / `configuredTextView()` (`EditorView.swift:705`) sets up the `LinkAwareTextView` and assign `textView.aiAppState = appState` (the `RawEditor` already has access to `appState` via the binding chain — pass it through; if `RawEditor` doesn't currently hold `appState`, thread it from `EditorView` at line 181-336 where `@EnvironmentObject var appState` is available).

- [ ] **Step 7: Build + relaunch and verify the full flow**

Run the build+relaunch command. Then verify by hand:
1. Open a note, click into a line → ✨ appears at the line end.
2. Click ✨ → bar opens below; type a prompt; press Generate → text streams in at the cursor.
3. Select a sentence → ✨ appears past the selection; click it → bar opens in rewrite mode; submit → original goes red/struck-through, new text streams green; Accept replaces, Reject restores.
4. In the prompt, type `@` + a few letters → suggestions appear; click one → inserts `@name`.
5. With no API key set, submitting shows "Add your Anthropic API key in Settings →".
6. Press Stop mid-stream → streaming halts, partial kept.

- [ ] **Step 8: Commit**

```bash
cd /Users/dep/Sites/synapse-notes/macOS && git add SynapseNotes/EditorView.swift && \
git commit -m "feat(ai): wire inline AI editing into the editor (✨, streaming, diff)"
```

---

## Self-Review

**Spec coverage:**
- Active-line ✨ → Task 9 Step 2/3. ✅
- Selection ✨ + inline diff accept/reject → Task 6 (logic) + Task 9 Step 5 (coloring). ✅
- API key in Keychain → Task 2 + Task 7. ✅
- Model picker (Haiku/Sonnet/Opus), per-request + persisted default → Task 1 + Task 7 + Task 8 bar picker. ✅
- `@note`/`@dir` autocomplete → Task 3 (resolve) + Task 8 (suggestions UI). ✅
- Streaming → Task 5 + Task 9 Step 4. ✅
- Stop/Esc cancel keeping partial → Task 6 `cancel` + Task 9 `stopAIStream`. ✅
- Inline error states (no key / 401 / network / missing ref / truncation) → Task 9 Step 4 `handleAIError` + resolver flags. ✅
- Current-note + @-refs implicit context → Task 4. ✅
- Direct URLSession SSE, no SDK → Task 5. ✅

**Placeholder scan:** No TBD/TODO. Every code step shows complete code. The few "confirm against existing signature" notes (Task 7 init, `commandPaletteScoreByFilename` label) are verification instructions tied to specific file:line anchors, not deferred work.

**Type consistency:** `AIModel.apiID`/`displayName`/`init(apiID:)` consistent across Tasks 1, 4, 7, 8. `AIContextResolver.Block(name:body:)` consistent across Tasks 3, 4, 9. `AnthropicClient.ClientError` cases `.invalidKey`/`.server(status:)`/`.badResponse` consistent across Tasks 5, 9. `InlineAIController` methods `beginGenerate`/`beginRewrite`/`appendDelta`/`cancel`/`accept`/`reject` and published `originalRange`/`newRange` consistent across Tasks 6, 9. `AIRequestBuilder.build(mode:prompt:noteText:selection:context:model:)` consistent across Tasks 4, 9.

## Notes for the implementer
- Tasks 1–6 are pure TDD and can each be done and reviewed independently.
- Tasks 7–9 touch existing files; after each, run the **build + relaunch** command before requesting review (mandatory per repo rules — overrides minimize-verification-loops).
- If `xcodebuild test` can't resolve the Keychain entitlement in the test host (Task 2), flag it at the checkpoint rather than weakening the test — the production app entitlement supports generic-password items.
- Respect the typing-perf hot path: the selection-change call to `refreshAISparkle()` must go through the existing debounce, never add synchronous parsing per caret move.
