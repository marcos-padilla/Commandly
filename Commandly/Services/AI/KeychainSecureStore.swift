import Foundation
import Security
import SecurityKit

/// Keychain-backed secure storage for provider credentials and other application secrets.
///
/// Items use the generic-password class, the injected service and optional access group, and the
/// logical `SecureStoreKey` as their stable account identifier. Values are available only while the
/// device is unlocked and never migrate to another device through a backup.
actor KeychainSecureStore: SecureStoring {
    private let service: String
    private let accessGroup: String?

    /// Creates a Keychain store scoped to one service and optional shared access group.
    ///
    /// - Throws: `SecureStoreError.invalidConfiguration` when either supplied identifier is empty.
    init(service: String, accessGroup: String? = nil) throws {
        guard service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SecureStoreError.invalidConfiguration
        }
        if let accessGroup,
           accessGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SecureStoreError.invalidConfiguration
        }
        self.service = service
        self.accessGroup = accessGroup
    }

    func read(_ key: SecureStoreKey) async throws -> Data? {
        try Task.checkCancellation()
        var query = try baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStoreError.invalidData
            }
            try Task.checkCancellation()
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(for: status)
        }
    }

    func write(_ key: SecureStoreKey, value: Data) async throws {
        try Task.checkCancellation()
        let query = try baseQuery(for: key)
        var attributes = query
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try Task.checkCancellation()
            let updatedValues: [String: Any] = [
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                updatedValues as CFDictionary
            )
            if updateStatus == errSecSuccess {
                return
            }

            // Another process may remove the item between the duplicate result and the update.
            // Retry the add once so the operation still has deterministic add-or-update behavior.
            if updateStatus == errSecItemNotFound {
                try Task.checkCancellation()
                let retryStatus = SecItemAdd(attributes as CFDictionary, nil)
                guard retryStatus == errSecSuccess else {
                    throw Self.error(for: retryStatus)
                }
                return
            }
            throw Self.error(for: updateStatus)
        default:
            throw Self.error(for: addStatus)
        }
    }

    func delete(_ key: SecureStoreKey) async throws {
        try Task.checkCancellation()
        let status = SecItemDelete(try baseQuery(for: key) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw Self.error(for: status)
        }
    }

    private func baseQuery(for key: SecureStoreKey) throws -> [String: Any] {
        guard key.isValid else {
            throw SecureStoreError.invalidKey
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Converts Keychain statuses to fixed errors that contain no key, value, or raw status payload.
    private static func error(for status: OSStatus) -> SecureStoreError {
        switch status {
        case errSecAuthFailed, errSecMissingEntitlement:
            return .accessDenied
        case errSecInteractionNotAllowed, errSecUserCanceled:
            return .interactionNotAllowed
        case errSecNotAvailable:
            return .unavailable
        case errSecDecode:
            return .invalidData
        case errSecParam:
            return .invalidConfiguration
        default:
            return .operationFailed
        }
    }
}
