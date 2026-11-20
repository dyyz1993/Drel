import Foundation
import Security

public struct DrelOAuthKeychainError: Error, Equatable {
    public let status: OSStatus
}

public final class DrelOAuthKeychainStore {
    public struct Record: Codable, Equatable {
        public let grantID: String
        public let refreshToken: String
    }

    private let service: String
    private let lock = NSLock()

    public init(service: String = "com.webbridgekit.superapp.oauth") {
        self.service = service
    }

    public func save(_ record: Record, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(record)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw DrelOAuthKeychainError(status: updateStatus) }
        } else {
            guard status == errSecSuccess else { throw DrelOAuthKeychainError(status: status) }
        }
    }

    public func save(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw DrelOAuthKeychainError(status: updateStatus) }
        } else {
            guard status == errSecSuccess else { throw DrelOAuthKeychainError(status: status) }
        }
    }

    public func load(account: String) throws -> Record? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw DrelOAuthKeychainError(status: status)
        }
        guard let data = result as? Data else { throw DrelOAuthKeychainError(status: errSecItemNotFound) }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    public func loadData(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw DrelOAuthKeychainError(status: status)
        }
        return result as? Data
    }

    public func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DrelOAuthKeychainError(status: status)
        }
    }

    public func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DrelOAuthKeychainError(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public protocol DrelOAuthTokenStoring {
    func saveRefreshToken(_ token: String, account: String) throws
    func loadRefreshToken(account: String) throws -> String?
    func delete(account: String) throws
    func removeAll() throws
}

public struct DrelOAuthKeychainTokenStore: DrelOAuthTokenStoring {
    private let store: DrelOAuthKeychainStore

    public init(service: String = "com.webbridgekit.superapp.oauth") {
        self.store = DrelOAuthKeychainStore(service: service)
    }

    public func saveRefreshToken(_ token: String, account: String) throws {
        guard !token.isEmpty else { throw DrelOAuthError.invalidRequest("empty refresh token") }
        try store.save(.init(grantID: account, refreshToken: token), account: account)
    }

    public func loadRefreshToken(account: String) throws -> String? {
        try store.load(account: account)?.refreshToken
    }

    public func delete(account: String) throws {
        try store.delete(account: account)
    }

    public func removeAll() throws {
        try store.removeAll()
    }
}

public struct DrelOAuthKeychainGrantMetadataStore {
    private let store: DrelOAuthKeychainStore

    public init(service: String = "com.webbridgekit.superapp.oauth") {
        self.store = DrelOAuthKeychainStore(service: service)
    }

    public func save(_ grant: DrelOAuthGrant) throws {
        try store.save(try JSONEncoder().encode(grant), account: "metadata|\(grant.contextKey)")
    }

    public func load(contextKey: String) throws -> DrelOAuthGrant? {
        guard let data = try store.loadData(account: "metadata|\(contextKey)") else { return nil }
        return try JSONDecoder().decode(DrelOAuthGrant.self, from: data)
    }

    public func delete(contextKey: String) throws {
        try store.delete(account: "metadata|\(contextKey)")
    }
}
