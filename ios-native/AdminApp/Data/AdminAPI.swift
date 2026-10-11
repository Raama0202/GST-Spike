import Foundation

/// Typed wrapper over the real FastAPI admin + super-admin routes — the same
/// endpoints the web dashboard uses, so no backend changes are required.
struct AdminAPI: Sendable {
    let api: APIClient

    private struct Remarks: Encodable { let remarks: String? }

    // MARK: Auth

    func login(email: String, password: String) async throws -> AdminLoginResponse {
        struct Body: Encodable { let email: String; let password: String }
        let body = try JSONEncoder().encode(Body(email: email, password: password))
        let data = try await api.raw(.post, "/admin/auth/login", body: body, authenticated: false)
        do {
            return try JSONDecoder().decode(AdminLoginResponse.self, from: data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError(kind: .decoding, status: nil, message: "Unexpected response from the login service.")
        }
    }

    func logout(refreshToken: String) async {
        struct Body: Encodable { let refreshToken: String }
        guard let body = try? JSONEncoder().encode(Body(refreshToken: refreshToken)) else { return }
        _ = try? await api.raw(.post, "/auth/logout", body: body, authenticated: false)
    }

    func activateCompany(code: String) async throws -> String {
        struct Body: Encodable { let activationCode: String }
        let body = try JSONEncoder().encode(Body(activationCode: code))
        let data = try await api.raw(.post, "/super/companies/activate", body: body, authenticated: false)
        let result = try? JSONDecoder().decode(StatusResult.self, from: data)
        return result?.status ?? "active"
    }

    // MARK: Dashboard & invoices

    func dashboard() async throws -> DashboardStats {
        try await api.get("/admin/dashboard")
    }

    static let invoicePageSize = 50

    /// Returns one page plus whether more pages exist on the server.
    func invoices(status: String?, search: String? = nil, page: Int = 1) async throws -> (items: [AdminInvoice], hasMore: Bool) {
        let response: ItemsResponse<AdminInvoice> = try await api.get(
            "/admin/invoices",
            query: ["status": status, "q": search, "page": String(page), "pageSize": String(Self.invoicePageSize)]
        )
        let hasMore = response.total.map { page * Self.invoicePageSize < $0 } ?? false
        return (response.items, hasMore)
    }

    func invoice(_ id: String) async throws -> AdminInvoice {
        try await api.get("/admin/invoices/\(id)")
    }

    func decide(_ id: String, decision: InvoiceDecision, remarks: String?) async throws -> AdminInvoice {
        try await api.send(.post, "/admin/invoices/\(id)/\(decision.rawValue)", json: Remarks(remarks: remarks))
    }

    // MARK: Team

    func employees() async throws -> [AdminEmployee] {
        let response: ItemsResponse<AdminEmployee> = try await api.get("/admin/employees")
        return response.items
    }

    func createEmployee(_ input: EmployeeInput) async throws -> AdminEmployee {
        try await api.send(.post, "/admin/employees", json: input)
    }

    func updateEmployee(_ id: String, _ input: EmployeeInput) async throws -> AdminEmployee {
        try await api.send(.patch, "/admin/employees/\(id)", json: input)
    }

    func deactivateEmployee(_ id: String) async throws {
        try await api.sendVoid(.delete, "/admin/employees/\(id)")
    }

    // MARK: Catalog

    func catalog(_ kind: CatalogKind) async throws -> [CatalogItem] {
        let response: ItemsResponse<CatalogItem> = try await api.get(kind.path)
        return response.items
    }

    func createCatalog(_ kind: CatalogKind, _ input: CatalogInput) async throws -> CatalogItem {
        try await api.send(.post, kind.path, json: input)
    }

    func updateCatalog(_ kind: CatalogKind, id: String, _ input: CatalogInput) async throws -> CatalogItem {
        try await api.send(.patch, "\(kind.path)/\(id)", json: input)
    }

    func deactivateCatalog(_ kind: CatalogKind, id: String) async throws {
        try await api.sendVoid(.delete, "\(kind.path)/\(id)")
    }

    // MARK: Settings & announcements

    func settings() async throws -> CompanySettings {
        try await api.get("/admin/company/settings")
    }

    func updateSettings(_ input: CompanySettingsInput) async throws -> CompanySettings {
        try await api.send(.patch, "/admin/company/settings", json: input)
    }

    func announce(title: String, body: String) async throws -> Int {
        struct Body: Encodable { let title: String; let body: String }
        struct Result: Decodable { let created: Int? }
        let result: Result = try await api.send(.post, "/admin/notifications/announcements", json: Body(title: title, body: body))
        return result.created ?? 0
    }

    func notifications() async throws -> [AdminNotification] {
        let response: ItemsResponse<AdminNotification> = try await api.get("/admin/notifications")
        return response.items
    }

    /// Server-side grouped history (one row per broadcast). Older servers only
    /// expose POST on this path, so fall back to grouping the raw rows.
    func announcementHistory() async throws -> [AnnouncementGroup] {
        do {
            let response: ItemsResponse<AnnouncementGroup> = try await api.get("/admin/notifications/announcements")
            return response.items
        } catch let error as APIError where error.kind == .notFound || error.status == 405 {
            let response: ItemsResponse<AdminNotification> = try await api.get(
                "/admin/notifications",
                query: ["type": "companyAnnouncement", "pageSize": "500"]
            )
            return AnnouncementGroup.grouping(response.items)
        }
    }

    // MARK: ITC

    private func itcQuery(_ period: String, _ type: GSTReturnType, status: String? = nil) -> [String: String?] {
        ["period": period, "returnType": type.rawValue, "status": status]
    }

    func itcSummary(period: String, type: GSTReturnType) async throws -> ITCSummary {
        try await api.get("/admin/itc/summary", query: itcQuery(period, type))
    }

    func itcMatches(period: String, type: GSTReturnType, status: ITCMatchStatus?) async throws -> [ITCMatch] {
        let response: ItemsResponse<ITCMatch> = try await api.get("/admin/itc/matches", query: itcQuery(period, type, status: status?.rawValue))
        return response.items
    }

    func itcImports(period: String) async throws -> [ITCImport] {
        let response: ItemsResponse<ITCImport> = try await api.get("/admin/itc/imports", query: ["period": period])
        return response.items
    }

    func itcImport(period: String, type: GSTReturnType, fileName: String, data: Data) async throws -> ITCSummary {
        var form = MultipartForm()
        form.addField("period", period)
        form.addField("returnType", type.rawValue)
        let mime: String
        switch (fileName as NSString).pathExtension.lowercased() {
        case "csv": mime = "text/csv"
        case "xls": mime = "application/vnd.ms-excel"
        case "json": mime = "application/json"
        default: mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
        form.addFile("file", filename: fileName, mimeType: mime, data: data)
        return try await api.upload("/admin/itc/import", form: form, timeout: 180)
    }

    func itcReconcile(period: String, type: GSTReturnType) async throws -> ITCSummary {
        try await api.send(.post, "/admin/itc/reconcile", query: itcQuery(period, type))
    }

    func itcExport(period: String, type: GSTReturnType, status: ITCMatchStatus?) async throws -> ITCExport {
        try await api.get("/admin/itc/matches/export", query: ["period": period, "returnType": type.rawValue, "status": status?.rawValue ?? ""])
    }

    func itcRemind(matchId: String) async throws -> ITCReminderLink {
        try await api.send(.post, "/admin/itc/matches/\(matchId)/remind")
    }

    func itcRemindMissing(period: String, type: GSTReturnType) async throws -> ITCReminderBatch {
        try await api.send(.post, "/admin/itc/remind-missing", query: itcQuery(period, type))
    }

    func itcFollowUps() async throws -> [ITCFollowUp] {
        let response: ItemsResponse<ITCFollowUp> = try await api.get("/admin/itc/reminders", query: ["status": "manual_followup"])
        return response.items
    }

    func itcUpdateFollowUp(_ id: String, called: Bool? = nil, promisedBy: Date? = nil, resolved: Bool? = nil) async throws {
        struct Body: Encodable {
            let called: Bool?
            let promisedBy: String?
            let resolved: Bool?
        }
        try await api.sendVoid(.patch, "/admin/itc/reminders/\(id)", json: Body(called: called, promisedBy: promisedBy.map(DateParser.dayString), resolved: resolved))
    }
}
