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

    func test_rewrite_inMiddle_accept_replacesCorrectSpan() {
        // "Hello WORLD!" — select "WORLD" (location 6, length 5), rewrite to "earth"
        let storage = makeStorage("Hello WORLD!")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 6, length: 5))
        c.appendDelta("earth")
        c.accept()
        XCTAssertEqual(storage.string, "Hello earth!")
    }

    func test_rewrite_inMiddle_reject_leavesOriginal() {
        let storage = makeStorage("Hello WORLD!")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 6, length: 5))
        c.appendDelta("earth")
        c.reject()
        XCTAssertEqual(storage.string, "Hello WORLD!")
    }

    // MARK: fixed behaviors

    func test_appendDelta_beforeBegin_isNoOp() {
        let storage = makeStorage("abc")
        let c = InlineAIController()
        c.appendDelta("X")
        XCTAssertEqual(storage.string, "abc")
    }

    func test_accept_inGenerateMode_doesNotMutate() {
        let storage = makeStorage("abc")
        let c = InlineAIController()
        c.beginGenerate(in: storage, at: 3)
        c.appendDelta("XY")          // "abcXY"
        c.accept()                   // wrong mode for accept → no-op
        XCTAssertEqual(storage.string, "abcXY")
    }

    func test_beginRewrite_whileActive_isIgnored() {
        let storage = makeStorage("Hello WORLD!")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 6, length: 5))
        c.appendDelta("earth")       // "Hello WORLDearth!", original (6,5)
        // A second begin must be ignored so the first session's ranges stay intact.
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 5))
        c.accept()                   // resolves the FIRST session
        XCTAssertEqual(storage.string, "Hello earth!")
    }

    func test_appendDelta_multibyteEmoji_tracksUTF16Length() {
        let storage = makeStorage("ab")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 2))
        c.appendDelta("👩‍🚀")          // family/ZWJ emoji: NSString length 5
        c.accept()                   // deletes original "ab", leaves the emoji
        XCTAssertEqual(storage.string, "👩‍🚀")
    }

    func test_reject_withNoDeltas_isSafeNoOpOnNewText() {
        let storage = makeStorage("keep me")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 4)) // "keep"
        c.reject()                   // zero deltas appended; deleting empty newRange is safe
        XCTAssertEqual(storage.string, "keep me")
    }

    // MARK: discardOutput (Retry support)

    func test_discardOutput_generate_removesInsertedTextAndIdles() {
        let storage = makeStorage("ab")
        let c = InlineAIController()
        c.beginGenerate(in: storage, at: 2)
        c.appendDelta("XYZ")         // "abXYZ"
        c.discardOutput()
        XCTAssertEqual(storage.string, "ab")
        XCTAssertEqual(c.mode, .idle)
    }

    func test_discardOutput_rewrite_removesNewTextKeepsOriginal() {
        let storage = makeStorage("The fox.")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 0, length: 8))
        c.appendDelta("A fox.")      // "The fox.A fox."
        c.discardOutput()
        XCTAssertEqual(storage.string, "The fox.")
        XCTAssertEqual(c.mode, .idle)
    }

    func test_retryFlow_generate_replacesRatherThanAppends() {
        // Simulates Retry: discard the first generation, then re-begin and stream again.
        // Regression test for the bug where Retry appended onto the previous output.
        let storage = makeStorage("Start: ")
        let c = InlineAIController()
        c.beginGenerate(in: storage, at: 7)
        c.appendDelta("first attempt")   // "Start: first attempt"
        c.discardOutput()                // back to "Start: "
        c.beginGenerate(in: storage, at: 7)
        c.appendDelta("second attempt")
        XCTAssertEqual(storage.string, "Start: second attempt")
    }

    func test_retryFlow_rewrite_replacesRatherThanAppends() {
        let storage = makeStorage("Hello WORLD!")
        let c = InlineAIController()
        c.beginRewrite(in: storage, selection: NSRange(location: 6, length: 5)) // "WORLD"
        c.appendDelta("earth")           // "Hello WORLDearth!"
        c.discardOutput()                // back to "Hello WORLD!"
        c.beginRewrite(in: storage, selection: NSRange(location: 6, length: 5))
        c.appendDelta("mars")
        c.accept()
        XCTAssertEqual(storage.string, "Hello mars!")
    }

    func test_discardOutput_whenIdle_isNoOp() {
        let storage = makeStorage("untouched")
        let c = InlineAIController()
        c.discardOutput()
        XCTAssertEqual(storage.string, "untouched")
        XCTAssertEqual(c.mode, .idle)
    }
}
