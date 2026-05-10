import Foundation
import Security

public protocol SecretStoring: Sendable {
    func save(_ value: String, for key: KeychainStore.Key) -> Bool
    func load(_ key: KeychainStore.Key) -> String?
    func delete(_ key: KeychainStore.Key)
}

public final class KeychainStore: SecretStoring, @unchecked Sendable {
    public enum Key: String, Sendable {
        case serverPassword = "com.hermesmobile.serverPassword"
        case authCookie = "com.hermesmobile.authCookie"
    }

    public static let shared = KeychainStore(service: "com.anderson.hermesmobile")

    private let service: String

    public init(service: String) {
        self.service = service
    }

    @discardableResult
    public func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var newItem = query
            newItem.merge(attributes, uniquingKeysWith: { $1 })
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            return addStatus == errSecSuccess
        default:
            return false
        }
    }

    public func load(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#if DEBUG
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [KeychainStore.Key: String] = [:]
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func save(_ value: String, for key: KeychainStore.Key) -> Bool {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
        return true
    }

    public func load(_ key: KeychainStore.Key) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func delete(_ key: KeychainStore.Key) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
#endif
