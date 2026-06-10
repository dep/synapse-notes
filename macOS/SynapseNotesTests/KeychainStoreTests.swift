import XCTest
@testable import Synapse

/// Exercises the `SecretStore` contract against the in-memory implementation. We do NOT
/// hit the real system keychain here: from an ad-hoc-signed test host that triggers a
/// login-password prompt (file-based keychain) or a silent entitlement failure
/// (data-protection keychain). `KeychainStore` is a thin SecItem wrapper over the same
/// contract; the behavior under test is the get/set/delete semantics.
final class KeychainStoreTests: XCTestCase {
    var store: SecretStore!

    override func setUp() {
        super.setUp()
        store = InMemorySecretStore()
    }

    override func tearDown() {
        store = nil
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

    func test_setWhitespaceOnly_deletesTheItem() {
        store.set("value")
        store.set("   \n ")
        XCTAssertNil(store.get())
    }

    func test_setTrimsWhitespace() {
        store.set("  sk-ant-padded  ")
        XCTAssertEqual(store.get(), "sk-ant-padded")
    }

    func test_delete_removesValue() {
        store.set("value")
        store.delete()
        XCTAssertNil(store.get())
    }

    func test_inMemoryStore_seedsInitialValue() {
        let seeded = InMemorySecretStore("preset")
        XCTAssertEqual(seeded.get(), "preset")
    }
}
