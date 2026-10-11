import SwiftUI
import Observation

/// Tenant configuration, cached per company so categories and branding work
/// offline. Refreshed on login and after every successful sync.
@MainActor
@Observable
final class CompanyConfigModel {
    private(set) var config: CompanyConfig? = nil
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var companyId: String? = nil

    init(api: APIClient) {
        self.api = api
    }

    var brandColor: Color { config?.brandColor ?? Brand.primary }
    var categories: [ExpenseCategory] { config?.categories ?? [] }

    func activate(companyId: String?) {
        self.companyId = companyId
        guard let companyId else {
            config = nil
            return
        }
        config = TenantStorage.read(CompanyConfig.self, from: cacheURL(companyId))
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let companyId else { return false }
        do {
            let fresh: CompanyConfig = try await api.get(EmployeeEndpoints.companyConfig)
            config = fresh
            TenantStorage.save(fresh, to: cacheURL(companyId))
            return true
        } catch {
            return false
        }
    }

    private func cacheURL(_ companyId: String) -> URL {
        TenantStorage.directory(companyId).appendingPathComponent("config.json")
    }
}
