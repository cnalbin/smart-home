import Foundation
import Security

/// 保存用户主动选择记住的登录信息；不进入 iCloud 或明文偏好设置。
struct RememberedLogin: Codable, Equatable {
    let username: String
    let password: String
}
struct CredentialVault {
    var account = "smart-home-remembered-login"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SmartHome.Login",
         kSecAttrAccount as String: account]
    }
    func read() -> RememberedLogin? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(RememberedLogin.self, from: data)
    }
    func save(_ login: RememberedLogin) throws {
        let data = try JSONEncoder().encode(login)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw VaultError.unavailable }
        } else if status != errSecSuccess { throw VaultError.unavailable }
    }
    func clear() { SecItemDelete(query as CFDictionary) }
    enum VaultError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法安全保存登录信息，请检查签名或取消记住密码后重试" }
    }
}
