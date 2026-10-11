import Foundation
import Observation

/// Employee authentication: OTP login, session restore with refresh-token
/// rotation, and tenant activation. Port of the Android auth repository.
@MainActor
@Observable
final class SessionModel {
    enum State: Equatable {
        case launching
        case signedOut
        case signedIn(Employee)
    }

    private(set) var state: State = .launching

    private let api: APIClient
    private let store: SessionStore
    private let invoices: InvoiceStore
    private let config: CompanyConfigModel
    private let notifications: NotificationsModel
    private let sync: SyncEngine
    @ObservationIgnored private var expiryObserver: NSObjectProtocol? = nil

    init(api: APIClient, store: SessionStore, invoices: InvoiceStore, config: CompanyConfigModel, notifications: NotificationsModel, sync: SyncEngine) {
        self.api = api
        self.store = store
        self.invoices = invoices
        self.config = config
        self.notifications = notifications
        self.sync = sync
        expiryObserver = NotificationCenter.default.addObserver(forName: .employeeSessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.expire() }
        }
    }

    var employee: Employee? {
        if case .signedIn(let employee) = state { return employee }
        return nil
    }

    var isSignedIn: Bool { employee != nil }

    // MARK: - Restore

    func restore() async {
        guard state == .launching else { return }
        guard store.hasSession, store.rememberLogin else {
            store.clear()
            state = .signedOut
            return
        }

        // Refresh before any protected call. Offline is fine: the cached
        // profile lets the employee keep scanning and queue uploads.
        if await TokenRefresher(api: api, store: store).attempt() == .rejected {
            store.clear()
            state = .signedOut
            return
        }

        var employee = store.employee
        if let fresh: Employee = try? await api.get(EmployeeEndpoints.me) {
            employee = fresh
            store.updateEmployee(fresh)
        }
        guard let employee else {
            state = .signedOut
            return
        }
        await activate(employee)
    }

    // MARK: - OTP

    func requestOtp(mobile: String) async throws {
        struct Body: Encodable { let mobile: String }
        let body = try JSONEncoder().encode(Body(mobile: mobile))
        _ = try await api.raw(.post, EmployeeEndpoints.requestOtp, body: body, authenticated: false)
    }

    func verifyOtp(mobile: String, otp: String, rememberLogin: Bool) async throws {
        struct Body: Encodable { let mobile: String; let otp: String }
        let body = try JSONEncoder().encode(Body(mobile: mobile, otp: otp))
        let data = try await api.raw(.post, EmployeeEndpoints.verifyOtp, body: body, authenticated: false)
        let session: OTPVerifyResponse
        do {
            session = try JSONDecoder().decode(OTPVerifyResponse.self, from: data)
        } catch {
            throw APIError(kind: .decoding, status: nil, message: "Unexpected response from authentication service.")
        }
        store.rememberLogin = rememberLogin
        store.save(tokens: session.tokens, employee: session.employee)
        await activate(session.employee)
    }

    // MARK: - Sign out

    func logout() async {
        if let refreshToken = store.refreshToken {
            struct Body: Encodable { let refreshToken: String }
            if let body = try? JSONEncoder().encode(Body(refreshToken: refreshToken)) {
                _ = try? await api.raw(.post, EmployeeEndpoints.logout, body: body, authenticated: false)
            }
        }
        sync.stop()
        await invoices.wipe()
        await invoices.open(companyId: nil)
        store.clear()
        config.activate(companyId: nil)
        notifications.activate(companyId: nil)
        LocalNotifier.setBadge(0)
        state = .signedOut
    }

    /// Refresh token revoked or expired: back to login, but keep the tenant's
    /// local data so queued invoices upload after the employee signs in again.
    private func expire() {
        guard isSignedIn else { return }
        sync.stop()
        store.clear()
        state = .signedOut
    }

    // MARK: - Activation

    private func activate(_ employee: Employee) async {
        await invoices.open(companyId: employee.companyId)
        config.activate(companyId: employee.companyId)
        notifications.activate(companyId: employee.companyId)
        state = .signedIn(employee)
        LocalNotifier.requestAuthorization()
        await sync.refreshCounts()
        sync.start()

        Task {
            await config.refresh()
            await registerDevice()
            await sync.syncNow()
        }
    }

    private func registerDevice() async {
        struct Body: Encodable {
            let deviceId: String
            let platform: String
            let appVersion: String
            let fcmToken: String?
        }
        let body = Body(deviceId: store.deviceId, platform: "ios", appVersion: AppInfo.shortVersion, fcmToken: nil)
        try? await api.sendVoid(.post, EmployeeEndpoints.deviceRegister, json: body)
    }
}
