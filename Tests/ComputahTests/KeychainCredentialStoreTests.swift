import XCTest
import Security
import LocalAuthentication
@testable import Computah

final class KeychainCredentialStoreTests: XCTestCase {
    private final class FakeKeychain {
        var value: Any?
        var updateFailure: OSStatus?
        var copyFailure: OSStatus?
        var deleteCalls = 0
        var addCalls = 0
        var queries: [[String: Any]] = []

        var operations: KeychainOperations {
            .init(copyMatching: { query in
                self.queries.append(query)
                if let status = self.copyFailure { return (status, nil) }
                return (self.value == nil ? errSecItemNotFound : errSecSuccess, self.value)
            }, add: { query in
                self.queries.append(query); self.addCalls += 1
                self.value = query[kSecValueData as String]
                return errSecSuccess
            }, update: { query, attributes in
                self.queries.append(query)
                if let status = self.updateFailure { return status }
                guard self.value != nil else { return errSecItemNotFound }
                self.value = attributes[kSecValueData as String]
                return errSecSuccess
            }, delete: { query in
                self.queries.append(query); self.deleteCalls += 1
                let status = self.value == nil ? errSecItemNotFound : errSecSuccess
                self.value = nil
                return status
            })
        }
    }

    func testSaveReplaceLoadAndRemoveUseOnlyInjectedStore() throws {
        let fake = FakeKeychain()
        let store = KeychainCredentialStore(operations: fake.operations)
        XCTAssertNil(try store.load())
        try store.save(" fixture-a \n")
        XCTAssertEqual(try store.load(), "fixture-a")
        try store.save("fixture-b")
        XCTAssertEqual(try store.load(), "fixture-b")
        XCTAssertEqual(fake.addCalls, 1)
        try store.remove()
        XCTAssertNil(try store.load())
        try store.remove()
        XCTAssertEqual(fake.deleteCalls, 2)
        for query in fake.queries {
            XCTAssertEqual(query[kSecAttrService as String] as? String, "com.lvl8.computah.api-key")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "openai")
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        }
    }

    func testFailedReplacementPreservesExistingCredential() throws {
        let fake = FakeKeychain()
        fake.value = Data("fixture-existing".utf8)
        fake.updateFailure = errSecAuthFailed
        let store = KeychainCredentialStore(operations: fake.operations)
        XCTAssertThrowsError(try store.save("fixture-new")) {
            XCTAssertEqual($0 as? CredentialStoreError, .operationFailed(errSecAuthFailed))
        }
        XCTAssertEqual(try store.load(), "fixture-existing")
        XCTAssertEqual(fake.deleteCalls, 0)
        XCTAssertEqual(fake.addCalls, 0)
    }

    func testEmptyKeyIsRejectedBeforeAnySecurityOperation() {
        let fake = FakeKeychain()
        let store = KeychainCredentialStore(operations: fake.operations)
        XCTAssertThrowsError(try store.save(" \n")) {
            XCTAssertEqual($0 as? CredentialStoreError, .emptyKey)
        }
        XCTAssertTrue(fake.queries.isEmpty)
    }

    func testStartupReadCannotDisplayAuthenticationPrompt() {
        let fake = FakeKeychain()
        fake.copyFailure = errSecInteractionNotAllowed
        let store = KeychainCredentialStore(operations: fake.operations)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? CredentialStoreError, .operationFailed(errSecInteractionNotAllowed))
        }
        XCTAssertEqual((fake.queries.first?[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed, true)
    }

    func testInvalidSavedDataReturnsSanitizedError() {
        let fake = FakeKeychain()
        fake.value = Data([0xff, 0xfe])
        let store = KeychainCredentialStore(operations: fake.operations)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? CredentialStoreError, .invalidStoredValue)
        }
    }
}
