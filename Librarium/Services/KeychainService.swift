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

    /// What the keychain said about a key. "Absent" and "couldn't read it"
    /// are different answers and the caller has to treat them differently:
    /// absent means the user is signed out, unreadable means ask again later.
    /// Collapsing the two is how a locked device turns into a lost session.
    enum Lookup: Equatable {
        /// The item was read.
        case found(String)
        /// The keychain answered, and there is no such item.
        case absent
        /// The keychain refused. The item may still be there, so nothing may
        /// delete it, but the read is not going to start working on its own.
        case unavailable(OSStatus)
        /// The keychain refused *because the device is locked* — a background
        /// launch, or before the first unlock after a reboot. This one does
        /// fix itself: the same read succeeds once the user unlocks.
        case locked(OSStatus)
    }

    /// Statuses that mean "ask again when the device is unlocked" rather than
    /// "something is wrong with this install".
    private static func isLockStatus(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecNotAvailable
    }

    func lookup(_ key: String) -> Lookup {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return .unavailable(errSecDecode)
            }
            return .found(value)
        case errSecItemNotFound:
            return .absent
        default:
            return Self.isLockStatus(status) ? .locked(status) : .unavailable(status)
        }
    }

    func get(_ key: String) -> String? {
        if case .found(let value) = lookup(key) { return value }
        return nil
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
