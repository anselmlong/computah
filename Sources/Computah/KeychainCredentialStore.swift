import Foundation
import Security
import LocalAuthentication

protocol CredentialStore {
    func load() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

enum CredentialStoreError: LocalizedError, Equatable {
    case emptyKey
    case invalidStoredValue
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey: return "Enter an API key before saving."
        case .invalidStoredValue: return "The saved API key could not be read. Replace or remove it in Settings."
        case .operationFailed(let status):
            switch status {
            case errSecInteractionNotAllowed: return "Keychain is locked or needs approval. Unlock your Mac and try again."
            case errSecAuthFailed, errSecUserCanceled: return "Keychain access was not approved. Try again when ready."
            case errSecNotAvailable: return "Keychain is unavailable. Try again after unlocking your Mac."
            default: return "The Keychain operation failed with code \(status). Try again."
            }
        }
    }
}

// Injected operations let tests exercise errors and replacement without opening Keychain
// or accessing the user's actual credential.
struct KeychainOperations {
    var copyMatching: ([String: Any]) -> (OSStatus, Any?)
    var add: ([String: Any]) -> OSStatus
    var update: ([String: Any], [String: Any]) -> OSStatus
    var delete: ([String: Any]) -> OSStatus

    static let system = KeychainOperations(
        copyMatching: { query in
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            return (status, value)
        },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        delete: { SecItemDelete($0 as CFDictionary) }
    )
}

struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account: String
    private let operations: KeychainOperations

    init(service: String = "com.lvl8.computah.api-key", account: String = "openai",
         operations: KeychainOperations = .system) {
        self.service = service; self.account = account; self.operations = operations
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> String? {
        var query = identity
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        // Startup must not open an unexpected authentication alert. An inaccessible
        // credential produces a recoverable Settings error instead.
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authentication
        let (status, value) = operations.copyMatching(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.operationFailed(status) }
        guard let data = value as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw CredentialStoreError.invalidStoredValue
        }
        return key
    }

    func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CredentialStoreError.emptyKey }
        let value: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = operations.update(identity, value)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = value[kSecValueData as String]
            item[kSecAttrLabel as String] = "Computah OpenAI API key"
            status = operations.add(item)
            // Another process may have added this same item after our update.
            if status == errSecDuplicateItem { status = operations.update(identity, value) }
        }
        guard status == errSecSuccess else { throw CredentialStoreError.operationFailed(status) }
    }

    func remove() throws {
        let status = operations.delete(identity)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.operationFailed(status)
        }
    }
}
