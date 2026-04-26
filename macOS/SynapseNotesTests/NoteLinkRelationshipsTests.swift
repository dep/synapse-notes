import XCTest
@testable import Synapse

/// Tests for `NoteLinkRelationships` — aggregate used by the Connections pane and link tooling.
final class NoteLinkRelationshipsTests: XCTestCase {

    func test_emptyLists_initializes() {
        let sut = NoteLinkRelationships(outbound: [], inbound: [], unresolved: [])
        XCTAssertTrue(sut.outbound.isEmpty)
        XCTAssertTrue(sut.inbound.isEmpty)
        XCTAssertTrue(sut.unresolved.isEmpty)
    }

    func test_preservesOrderAndCounts() {
        let a = URL(fileURLWithPath: "/vault/A.md")
        let b = URL(fileURLWithPath: "/vault/B.md")
        let c = URL(fileURLWithPath: "/vault/C.md")
        let sut = NoteLinkRelationships(
            outbound: [a, b],
            inbound: [c],
            unresolved: ["ghost", "missing"]
        )
        XCTAssertEqual(sut.outbound.count, 2)
        XCTAssertEqual(sut.inbound.count, 1)
        XCTAssertEqual(sut.unresolved, ["ghost", "missing"])
        XCTAssertEqual(sut.outbound.first, a)
        XCTAssertEqual(sut.outbound[1], b)
    }
}
