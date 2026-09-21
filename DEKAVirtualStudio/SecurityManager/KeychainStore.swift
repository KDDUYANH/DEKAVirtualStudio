//
//  KeychainStore.swift
//  The ONLY place secrets are persisted. Items are device-only (not in iCloud Keychain, not in
//  backups restored to another device) and readable after first unlock (so a stream can
//  reconnect while the phone is locked in a rig).
//

import Foundation
import Security

enum KeychainError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case encoding
    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): return "Keychain error \(s)."
        case .encoding: return "Keychain data could not be encoded."
        }
    }
}

struct KeychainStore {
    let service: String

    init(service: String = "com.dtek.studio.secure") { self.service = service }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static let simFallback = Locked<[String: Data]>([:])
    private func fallbackKey(_ account: String) -> String { "\(service):\(account)" }

    private static func isMissingEntitlement(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == -34018
    }

    func set(_ data: Data, for account: String) throws {
        var query = base(account)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(attrs) { $1 }
            let add = SecItemAdd(query as CFDictionary, nil)
            if Self.isMissingEntitlement(add) {
                Self.simFallback.mutate { $0[fallbackKey(account)] = data }
                return
            }
            guard add == errSecSuccess else { throw KeychainError.unexpectedStatus(add) }
        } else if Self.isMissingEntitlement(status) {
            Self.simFallback.mutate { $0[fallbackKey(account)] = data }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(for account: String) throws -> Data? {
        if let fallback = Self.simFallback.get()[fallbackKey(account)] { return fallback }
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        if Self.isMissingEntitlement(status) {
            return Self.simFallback.get()[fallbackKey(account)]
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return out as? Data
    }

    func delete(_ account: String) throws {
        Self.simFallback.mutate { $0.removeValue(forKey: fallbackKey(account)) }
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound || Self.isMissingEntitlement(status) else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // Convenience
    func setString(_ s: String, for account: String) throws {
        guard let d = s.data(using: .utf8) else { throw KeychainError.encoding }
        try set(d, for: account)
    }
    func string(for account: String) -> String? {
        (try? data(for: account)).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
    }
    func setCodable<T: Encodable>(_ v: T, for account: String) throws { try set(JSONEncoder().encode(v), for: account) }
    func codable<T: Decodable>(_ t: T.Type, for account: String) -> T? {
        (try? data(for: account)).flatMap { $0 }.flatMap { try? JSONDecoder().decode(t, from: $0) }
    }
}
