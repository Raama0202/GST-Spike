import Foundation

/// Tokens + employee profile in the Keychain, with an in-memory mirror so the
/// API client can read credentials synchronously from any thread.
final class SessionStore: @unchecked Sendable {
    private enum Key {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let employee = "employee"
        static let rememberLogin = "remember_login"
    }

    private let keychain = KeychainStore(service: "com.gstexpenses.gstexpensescanner.session")
    private let lock = NSLock()
    private var accessToken: String?
    private var cachedRefreshToken: String?
    private var cachedEmployee: Employee?

    let deviceId: String

    init() {
        deviceId = keychain.deviceId()
        accessToken = keychain.string(Key.accessToken)
        cachedRefreshToken = keychain.string(Key.refreshToken)
        cachedEmployee = keychain.codable(Employee.self, Key.employee)
    }

    func credentials() -> APICredentials {
        lock.lock(); defer { lock.unlock() }
        return APICredentials(accessToken: accessToken, companyId: cachedEmployee?.companyId)
    }

    var refreshToken: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedRefreshToken
    }

    var employee: Employee? {
        lock.lock(); defer { lock.unlock() }
        return cachedEmployee
    }

    var hasSession: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedEmployee != nil && !(cachedRefreshToken ?? accessToken ?? "").isEmpty
    }

    var rememberLogin: Bool {
        get { keychain.string(Key.rememberLogin) != "false" }
        set { keychain.set(newValue ? "true" : "false", for: Key.rememberLogin) }
    }

    func save(tokens: AuthTokens, employee: Employee) {
        lock.lock()
        accessToken = tokens.accessToken
        cachedRefreshToken = tokens.refreshToken
        cachedEmployee = employee
        lock.unlock()
        keychain.set(tokens.accessToken, for: Key.accessToken)
        keychain.set(tokens.refreshToken, for: Key.refreshToken)
        keychain.setCodable(employee, for: Key.employee)
    }

    func updateTokens(_ tokens: AuthTokens) {
        lock.lock()
        accessToken = tokens.accessToken
        if !tokens.refreshToken.isEmpty { cachedRefreshToken = tokens.refreshToken }
        let refresh = cachedRefreshToken
        lock.unlock()
        keychain.set(tokens.accessToken, for: Key.accessToken)
        keychain.set(refresh, for: Key.refreshToken)
    }

    func updateEmployee(_ employee: Employee) {
        lock.lock()
        cachedEmployee = employee
        lock.unlock()
        keychain.setCodable(employee, for: Key.employee)
    }

    func clear() {
        lock.lock()
        accessToken = nil
        cachedRefreshToken = nil
        cachedEmployee = nil
        lock.unlock()
        keychain.remove(Key.accessToken, Key.refreshToken, Key.employee)
    }
}

/// Refresh-token rotation used by `APIClient` on any 401.
struct TokenRefresher: Sendable {
    enum Outcome { case refreshed, rejected, unavailable }

    let api: APIClient
    let store: SessionStore

    /// Used by `APIClient`; a rejected refresh token ends the session.
    func refresh() async -> Bool {
        switch await attempt() {
        case .refreshed:
            return true
        case .rejected:
            await MainActor.run {
                NotificationCenter.default.post(name: .employeeSessionExpired, object: nil)
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
            let data = try await api.raw(.post, EmployeeEndpoints.refreshToken, body: body, authenticated: false, allowRefresh: false)
            let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
            store.updateTokens(tokens)
            return .refreshed
        } catch let error as APIError where error.kind == .unauthorized {
            return .rejected
        } catch {
            return .unavailable
        }
    }
}
