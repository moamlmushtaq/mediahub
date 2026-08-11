import Foundation
import Security

/// Where the session token lives between launches.
///
/// The Keychain rather than `UserDefaults`, and the difference is not
/// theoretical: this token is a bearer credential valid for thirty days, and
/// `UserDefaults` is a plist in the app's container that any process running as
/// the same user can read. The Keychain is encrypted at rest and gated by the
/// login session.
///
/// `kSecAttrAccessibleAfterFirstUnlock` rather than the default so the app can
/// restore a session on login without the viewer typing anything, while the
/// token still stays unreadable on a machine that has been shut down and not
/// yet unlocked.
enum Keychain {
    /// Namespaced so a future companion tool cannot collide with it.
    private static let service = "com.msol.mediahub.mac"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> String? {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }

        return value
    }

    /// Writes, replacing whatever was there. Passing `nil` deletes.
    ///
    /// Delete-then-add rather than `SecItemUpdate`: an update on a missing item
    /// fails, an add on an existing one fails, and branching on which case
    /// applies is three round trips to avoid one harmless delete.
    @discardableResult
    static func write(_ value: String?, account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)

        guard let value, !value.isEmpty else { return true }

        var insert = query(account)
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    enum Account {
        static let token = "session-token"
        /// The viewer, as JSON, so the app can draw a name on launch without
        /// waiting for a round trip that might fail.
        static let viewer = "session-viewer"
        /// The subtitle language chosen last, so the choice survives a restart.
        static let subtitleLanguage = "subtitle-language"
    }
}
