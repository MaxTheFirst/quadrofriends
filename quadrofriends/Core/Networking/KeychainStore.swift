import Foundation
import Security

/// Хранит Codable-значение в Keychain как generic password.
struct KeychainStore<Value: Codable> {
    let service: String
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> Value? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
