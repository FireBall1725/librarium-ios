import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private let service = "ca.fireball1725.librarium-ios"

    private init() {}

    /// Write a value, always with `kSecAttrAccessibleAfterFirstUnlock`.
    ///
    /// `AfterFirstUnlock` (rather than the default `WhenUnlocked`) means
    /// tokens stay readable across background scenarios — passcode
    /// re-locks, autosuspend, app-refresh tasks — once the device has
    /// been unlocked at least once since boot. That's what we want for
    /// refresh-on-launch flows.
    ///
    /// Accessibility class is set at insert time and can't be changed by
    /// `SecItemUpdate`. To migrate existing items written with the older
    /// default, we delete then re-add so the new entry picks up the
    /// upgraded class. Idempotent: nothing to delete on the first write.
    func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        delete(key)
        let attributes: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
