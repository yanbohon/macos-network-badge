import Foundation
import LocalAuthentication
import Security

enum SecretKey: String, CaseIterable {
    case password
    case accessToken
    case refreshToken
    case accessTokenExpiry
}

protocol SecretStoring {
    func read(_ key: SecretKey) throws -> String?
    func write(_ value: String, for key: SecretKey) throws
    func delete(_ key: SecretKey) throws
}

enum KeychainStoreError: Error {
    case unhandledStatus(OSStatus)
    case invalidData
    case interactionNotAllowed
}

final class KeychainStore: SecretStoring {
    static let service = "com.usagemonitor.app.sub2api"
    private enum AuthenticationUI {
        static let key = "u_AuthUI"
        static let fail = "u_AuthUIF"
    }

    private let service: String

    init(service: String = KeychainStore.service) {
        self.service = service
    }

    func read(_ key: SecretKey) throws -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery(for: key) as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed {
            throw KeychainStoreError.interactionNotAllowed
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainStoreError.invalidData
        }
        return value
    }

    func write(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(updateQuery(for: key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecInteractionNotAllowed {
            throw KeychainStoreError.interactionNotAllowed
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainStoreError.unhandledStatus(updateStatus)
        }

        var query = addQuery(for: key)
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(addStatus)
        }
    }

    func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(deleteQuery(for: key) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        if status == errSecInteractionNotAllowed {
            throw KeychainStoreError.interactionNotAllowed
        }
        throw KeychainStoreError.unhandledStatus(status)
    }

    func readQuery(for key: SecretKey) -> [String: Any] {
        var query = noAuthenticationUIQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    func updateQuery(for key: SecretKey) -> [String: Any] {
        noAuthenticationUIQuery(for: key)
    }

    func deleteQuery(for key: SecretKey) -> [String: Any] {
        noAuthenticationUIQuery(for: key)
    }

    private func addQuery(for key: SecretKey) -> [String: Any] {
        baseQuery(for: key)
    }

    private func noAuthenticationUIQuery(for key: SecretKey) -> [String: Any] {
        var query = baseQuery(for: key)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[AuthenticationUI.key] = AuthenticationUI.fail
        return query
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
