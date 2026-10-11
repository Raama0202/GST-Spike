import Foundation
import Security

/// Thin Keychain wrapper — the iOS counterpart of `flutter_secure_storage`.
/// Items stay readable after first unlock so background sync can authenticate.
struct KeychainStore: Sendable {
    let service: String

    func string(_ key: String) -> String? {
        guard let data = data(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for key: String) {
        setData(value.flatMap { $0.data(using: .utf8) }, for: key)
    }

    func data(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func setData(_ value: Data?, for key: String) {
        let query = baseQuery(key)
        guard let value else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func codable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = data(key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setCodable<T: Encodable>(_ value: T?, for key: String) {
        setData(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }

    func remove(_ keys: String...) {
        keys.forEach { set(nil, for: $0) }
    }

    /// Stable per-install identifier sent as `X-Device-Id`.
    func deviceId() -> String {
        if let existing = string("device_id"), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString.lowercased()
        set(fresh, for: "device_id")
        return fresh
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
