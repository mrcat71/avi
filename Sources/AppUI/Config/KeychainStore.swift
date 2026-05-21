import Foundation
import Security

/// Thin wrapper over Security framework `kSecClassGenericPassword` items.
/// All Avi tokens live under service `"com.avi"` keyed by an account name
/// chosen by the caller (typically `"avi.openai.apiKey"` or `"avi.account.<uuid>"`).
enum KeychainStore {
    private static let service = "com.avi"

    enum KeychainError: Error, CustomStringConvertible {
        case unexpected(OSStatus)
        var description: String {
            switch self {
            case .unexpected(let status):
                return "Keychain error \(status)"
            }
        }
    }

    static func setString(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        // Try update first; if the item doesn't exist, fall back to add.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unexpected(addStatus)
            }
            return
        }

        throw KeychainError.unexpected(updateStatus)
    }

    static func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deleteString(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes every Avi keychain entry. Used by "Reset all settings".
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
