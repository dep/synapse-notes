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
