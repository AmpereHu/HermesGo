@testable import HermesMobile
import XCTest

final class InMemorySecretStoreTests: XCTestCase {
    func test_saveLoadDelete() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.load(.serverPassword))

        XCTAssertTrue(store.save("hunter2", for: .serverPassword))
        XCTAssertEqual(store.load(.serverPassword), "hunter2")

        XCTAssertTrue(store.save("rotated", for: .serverPassword))
        XCTAssertEqual(store.load(.serverPassword), "rotated")

        store.delete(.serverPassword)
        XCTAssertNil(store.load(.serverPassword))
    }

    func test_independentKeys() {
        let store = InMemorySecretStore()
        store.save("pwd", for: .serverPassword)
        store.save("cookie", for: .authCookie)
        XCTAssertEqual(store.load(.serverPassword), "pwd")
        XCTAssertEqual(store.load(.authCookie), "cookie")
        store.delete(.serverPassword)
        XCTAssertNil(store.load(.serverPassword))
        XCTAssertEqual(store.load(.authCookie), "cookie")
    }
}

final class KeychainStoreTests: XCTestCase {
    /// Real keychain only available on real device / signed simulator.
    /// We verify the store accepts read/write but skip if not entitled.
    func test_keychainRoundTripIfAvailable() throws {
        let store = KeychainStore(service: "com.anderson.hermesmobile.tests")
        guard store.save("test-secret", for: .serverPassword) else {
            // Expected on unsigned simulators / Linux environments.
            throw XCTSkip("Keychain not available in this environment")
        }
        XCTAssertEqual(store.load(.serverPassword), "test-secret")
        store.delete(.serverPassword)
        XCTAssertNil(store.load(.serverPassword))
    }
}
