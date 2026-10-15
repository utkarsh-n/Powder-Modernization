import Foundation
import Security

enum CloudCredentialStore {
    private static let service = "dev.utkarsh.powder.scene-intelligence"
    private static let account = "openai-api-key"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeyError(status) }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try remove(); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(trimmed.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeyError(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError(status) }
    }

    private struct KeyError: Error, LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? {
            if status == errSecMissingEntitlement {
                return "Keychain requires a signed app build. Sign this target in Xcode to enable cloud credentials."
            }
            return "Keychain is unavailable (\(status))."
        }
    }
}
