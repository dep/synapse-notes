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
}
