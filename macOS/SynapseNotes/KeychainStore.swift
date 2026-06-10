import Foundation
import Security

/// A store for a single secret string (the Anthropic API key), abstracted so tests can
/// substitute an in-memory implementation and never touch the system keychain (which
/// prompts for the login password when an ad-hoc-signed test host accesses it).
protocol SecretStore {
    func get() -> String?
    func set(_ value: String)
    func delete()
}

/// Securely stores a single secret (the Anthropic API key) in the macOS Keychain.
/// One instance == one (service, account) slot.
struct KeychainStore: SecretStore {
    let service: String
    let account: String

    init(service: String = "com.SynapseNotes.anthropic", account: String = "apiKey") {
        self.service = service
        self.account = account
    }

    /// The identifying attributes shared by every operation.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Returns the stored secret, or nil if none is set.
    func get() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Removes the stored secret if present.
    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// An in-memory `SecretStore` for tests and previews — never touches the system keychain.
final class InMemorySecretStore: SecretStore {
    private var value: String?
    init(_ initial: String? = nil) { self.value = initial }

    func get() -> String? { (value?.isEmpty == false) ? value : nil }

    func set(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = trimmed.isEmpty ? nil : trimmed
    }

    func delete() { value = nil }
}
