import Foundation
import Observation

/// Email/password session for company admins. Super admins manage the
/// platform from the web dashboard only, so their accounts are refused here.
@MainActor
@Observable
final class AdminSession {
    enum State: Equatable {
        case launching
        case signedOut
        case signedIn(AdminUser)
    }

    private(set) var state: State = .launching

    @ObservationIgnored let store: AdminSessionStore
    @ObservationIgnored let client: APIClient
    @ObservationIgnored let api: AdminAPI
    @ObservationIgnored private var expiryObserver: NSObjectProtocol? = nil

    init() {
        let store = AdminSessionStore()
        let client = APIClient(deviceId: store.deviceId) { store.credentials() }
        let refresher = AdminTokenRefresher(api: client, store: store)
        client.setRefresher { await refresher.refresh() }
        self.store = store
        self.client = client
        self.api = AdminAPI(api: client)
        expiryObserver = NotificationCenter.default.addObserver(forName: .adminSessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.expire() }
        }
    }

    var user: AdminUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    func restore() async {
        guard state == .launching else { return }
        guard store.hasSession, let user = store.user, user.role == .companyAdmin else {
            store.clear()
            state = .signedOut
            return
        }
        if await AdminTokenRefresher(api: client, store: store).attempt() == .rejected {
            store.clear()
            state = .signedOut
            return
        }
        state = .signedIn(user)
    }

    func login(email: String, password: String) async throws {
        let response = try await api.login(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
        guard response.user.role == .companyAdmin else {
            if !response.tokens.refreshToken.isEmpty {
                await api.logout(refreshToken: response.tokens.refreshToken)
            }
            throw APIError(kind: .forbidden, status: 403, message: "Super admin accounts use the web dashboard. This app is for company administrators.")
        }
        guard !response.billingRequired else {
            if !response.tokens.refreshToken.isEmpty {
                await api.logout(refreshToken: response.tokens.refreshToken)
            }
            throw APIError(kind: .forbidden, status: 403, message: "Your subscription has expired. Sign in to the web dashboard to renew it, then use the app again.")
        }
        store.save(tokens: response.tokens, user: response.user)
        store.lastEmail = response.user.email
        state = .signedIn(response.user)
    }

    func logout() async {
        if let refreshToken = store.refreshToken {
            await api.logout(refreshToken: refreshToken)
        }
        store.clear()
        state = .signedOut
    }

    private func expire() {
        guard user != nil else { return }
        store.clear()
        state = .signedOut
    }
}
