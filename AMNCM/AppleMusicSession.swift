import Foundation
import Security

struct AppleMusicSession: Codable, Sendable {
    let developer: String
    let user: String
    let storefront: String

    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.shawnrain.am-ncm.apple-music",
        kSecAttrAccount as String: "web-session",
    ] }

    static func load() -> Self? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let values = [kSecValueData as String: data]
        let updated = SecItemUpdate(Self.query as CFDictionary, values as CFDictionary)
        let status = updated == errSecItemNotFound
            ? SecItemAdd(Self.query.merging(values) { _, new in new } as CFDictionary, nil)
            : updated
        guard status == errSecSuccess else {
            throw Engine.Failure("无法把 Apple Music 登录保存到钥匙串。")
        }
    }

    static func disconnect() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Engine.Failure("无法从钥匙串移除 Apple Music 登录。")
        }
    }
}
