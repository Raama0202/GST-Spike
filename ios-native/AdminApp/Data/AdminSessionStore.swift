import Foundation

extension Notification.Name {
    static let adminSessionExpired = Notification.Name("adminSessionExpired")
}

/// Admin tokens + user in the Keychain, mirrored in memory for the API client.
final class AdminSessionStore: @unchecked Sendable {
    private enum Key {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let user = "user"
        static let lastEmail = "last_email"
    }

    private let keychain = KeychainStore(service: "com.gstexpenses.gstexpenseadmin.session")
    private let lock = NSLock()
    private var accessToken: String?
    private var cachedRefreshToken: String?
    private var cachedUser: AdminUser?

    let deviceId: String

    init() {
        deviceId = keychain.deviceId()
        accessToken = keychain.string(Key.accessToken)
        cachedRefreshToken = keychain.string(Key.refreshToken)
        cachedUser = keychain.codable(AdminUser.self, Key.user)
    }

    func credentials() -> APICredentials {
        lock.lock(); defer { lock.unlock() }
        return APICredentials(accessToken: accessToken, companyId: cachedUser?.companyId)
    }

    var refreshToken: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedRefreshToken
    }

    var user: AdminUser? {
        lock.lock(); defer { lock.unlock() }
        return cachedUser
    }

    var hasSession: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedUser != nil && !(cachedRefreshToken ?? "").isEmpty
    }

    var lastEmail: String? {
        get { keychain.string(Key.lastEmail) }
        set { keychain.set(newValue, for: Key.lastEmail) }
    }

    func save(tokens: AdminTokens, user: AdminUser) {
        lock.lock()
        accessToken = tokens.accessToken
        cachedRefreshToken = tokens.refreshToken
        cachedUser = user
        lock.unlock()
        keychain.set(tokens.accessToken, for: Key.accessToken)
        keychain.set(tokens.refreshToken, for: Key.refreshToken)
        keychain.setCodable(user, for: Key.user)
    }

    func updateTokens(_ tokens: AdminTokens) {
        lock.lock()
        accessToken = tokens.accessToken
        if !tokens.refreshToken.isEmpty { cachedRefreshToken = tokens.refreshToken }
        let refresh = cachedRefreshToken
        lock.unlock()
        keychain.set(tokens.accessToken, for: Key.accessToken)
        keychain.set(refresh, for: Key.refreshToken)
    }

    func clear() {
        lock.lock()
        accessToken = nil
        cachedRefreshToken = nil
        cachedUser = nil
        lock.unlock()
        keychain.remove(Key.accessToken, Key.refreshToken, Key.user)
    }
}

struct AdminTokenRefresher: Sendable {
    enum Outcome { case refreshed, rejected, unavailable }

    let api: APIClient
    let store: AdminSessionStore

    func refresh() async -> Bool {
        switch await attempt() {
        case .refreshed:
            return true
        case .rejected:
            await MainActor.run {
                NotificationCenter.default.post(name: .adminSessionExpired, object: nil)
            }
            return false
        case .unavailable:
            return false
        }
    }

    func attempt() async -> Outcome {
        guard let refreshToken = store.refreshToken, !refreshToken.isEmpty else { return .rejected }
        do {
            let body = try JSONEncoder().encode(["refreshToken": refreshToken])
            let data = try await api.raw(.post, APIClient.refreshPath, body: body, authenticated: false, allowRefresh: false)
            store.updateTokens(try JSONDecoder().decode(AdminTokens.self, from: data))
            return .refreshed
        } catch let error as APIError where error.kind == .unauthorized {
            return .rejected
        } catch {
            return .unavailable
        }
    }
}
