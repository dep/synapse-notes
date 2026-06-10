import XCTest
@testable import Synapse

final class MarkdownPreviewRevealMemoTests: XCTestCase {
    // MARK: - Block reveal gate

    func test_canSkipBlockReveal_whileCaretStaysInRevealedBlock() {
        var memo = MarkdownPreviewRevealMemo()
        memo.noteRevealedBlock(NSRange(location: 10, length: 5))

        XCTAssertTrue(memo.canSkipBlockReveal(cursorLocation: 10))
        XCTAssertTrue(memo.canSkipBlockReveal(cursorLocation: 12))
        // Caret exactly at the block's end boundary still counts as inside,
        // matching MarkdownPreviewBlockReveal.make's containment rule.
        XCTAssertTrue(memo.canSkipBlockReveal(cursorLocation: 15))
    }

    func test_canSkipBlockReveal_falseWhenCaretCrossesBlockBoundary() {
        var memo = MarkdownPreviewRevealMemo()
        memo.noteRevealedBlock(NSRange(location: 10, length: 5))

        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 9))
        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 16))
    }

    func test_canSkipBlockReveal_falseWhenNoBlockRevealed() {
        var memo = MarkdownPreviewRevealMemo()
        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 0))

        // A reveal that found no block (caret on a blank line) must not gate either.
        memo.noteRevealedBlock(nil)
        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 0))
    }

    func test_textEdit_invalidatesBlockGate() {
        var memo = MarkdownPreviewRevealMemo()
        memo.noteRevealedBlock(NSRange(location: 0, length: 20))
        XCTAssertTrue(memo.canSkipBlockReveal(cursorLocation: 5))

        memo.noteTextChanged()

        // Same caret position, but the text changed underneath — must recompute.
        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 5))
    }

    func test_invalidateRevealedBlock_clearsGate() {
        var memo = MarkdownPreviewRevealMemo()
        memo.noteRevealedBlock(NSRange(location: 0, length: 20))

        memo.invalidateRevealedBlock()

        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: 5))
        XCTAssertNil(memo.revealedBlockRange)
    }

    // MARK: - Document parse memo

    func test_document_parsesOncePerTextVersion() {
        var memo = MarkdownPreviewRevealMemo()
        let source = "# Title\n\nBody with **bold** text"

        let first = memo.document(for: source)
        let second = memo.document(for: source)

        XCTAssertEqual(memo.parseCount, 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.source, source)
        XCTAssertFalse(first.blocks.isEmpty)
    }

    func test_document_reparsesAfterTextChange() {
        var memo = MarkdownPreviewRevealMemo()
        _ = memo.document(for: "# Title")
        XCTAssertEqual(memo.parseCount, 1)

        memo.noteTextChanged()
        let reparsed = memo.document(for: "# Title!")

        XCTAssertEqual(memo.parseCount, 2)
        XCTAssertEqual(reparsed.source, "# Title!")
    }

    func test_document_reparsesWhenLengthChangesWithoutVersionBump() {
        // Defensive second cache key: a missed noteTextChanged() must not serve a
        // parse whose ranges no longer fit the storage.
        var memo = MarkdownPreviewRevealMemo()
        _ = memo.document(for: "# Title")

        let reparsed = memo.document(for: "# Title plus more")

        XCTAssertEqual(memo.parseCount, 2)
        XCTAssertEqual(reparsed.source, "# Title plus more")
    }

    func test_sameBlockCaretMoves_doNoParseWork() {
        // End-to-end shape of the per-keystroke selection path: one parse after the
        // edit, then zero work while the caret moves within the revealed block.
        var memo = MarkdownPreviewRevealMemo()
        let source = "# Title\n\nBody paragraph"
        let document = memo.document(for: source)
        let reveal = MarkdownPreviewBlockReveal.make(document: document, cursorLocation: 2, isEditable: true)
        memo.noteRevealedBlock(reveal.blockRange)
        XCTAssertEqual(memo.parseCount, 1)

        for cursor in 0...7 where memo.canSkipBlockReveal(cursorLocation: cursor) == false {
            XCTFail("caret move to \(cursor) inside the heading block should be skipped")
        }
        XCTAssertEqual(memo.parseCount, 1, "same-block caret moves must not parse")

        // Crossing into the body paragraph must recompute (and may reuse the cached parse).
        let bodyCursor = (source as NSString).range(of: "Body").location
        XCTAssertFalse(memo.canSkipBlockReveal(cursorLocation: bodyCursor))
        _ = memo.document(for: source)
        XCTAssertEqual(memo.parseCount, 1, "recompute on block crossing reuses the cached parse")
    }
}
