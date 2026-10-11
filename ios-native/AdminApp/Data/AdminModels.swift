import SwiftUI

// MARK: - Auth

enum AdminRole: String, Codable, Sendable {
    case superAdmin = "super_admin"
    case companyAdmin = "company_admin"

    var title: String { self == .superAdmin ? "Super Admin" : "Company Admin" }
}

struct AdminUser: Codable, Equatable, Sendable {
    var id: String
    var email: String
    var role: AdminRole
    var companyId: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id"), let roleRaw = c.string("role"), let role = AdminRole(rawValue: roleRaw) else {
            throw APIError(kind: .forbidden, status: 403, message: "This account cannot use the admin app.")
        }
        self.id = id
        self.role = role
        email = c.string("email") ?? ""
        companyId = c.string("companyId", "company_id")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(email, forKey: "email")
        try c.encode(role.rawValue, forKey: "role")
        try c.encodeIfPresent(companyId, forKey: "companyId")
    }
}

struct AdminTokens: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let access = c.string("accessToken") else {
            throw APIError(kind: .decoding, status: nil, message: "Missing access token.")
        }
        accessToken = access
        refreshToken = c.string("refreshToken") ?? ""
    }
}

struct AdminLoginResponse: Decodable, Sendable {
    let tokens: AdminTokens
    let user: AdminUser
    /// The company's subscription has lapsed; only billing endpoints work until it's renewed.
    let billingRequired: Bool

    init(from decoder: Decoder) throws {
        tokens = try AdminTokens(from: decoder)
        let c = try decoder.container(keyedBy: AnyKey.self)
        user = try c.decode(AdminUser.self, forKey: "user")
        billingRequired = (try? c.decode(Bool.self, forKey: "billingRequired")) ?? false
    }
}

// MARK: - Dashboard

struct DashboardStats: Decodable, Sendable {
    var pendingCount = 0
    var todayUploads = 0
    var approvedCount = 0
    var rejectedCount = 0
    var returnedCount = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        pendingCount = c.int("pendingCount") ?? 0
        todayUploads = c.int("todayUploads") ?? 0
        approvedCount = c.int("approvedCount") ?? 0
        rejectedCount = c.int("rejectedCount") ?? 0
        returnedCount = c.int("returnedCount") ?? 0
    }

    var total: Int { pendingCount + approvedCount + rejectedCount + returnedCount }
}

// MARK: - Invoices

struct AdminInvoice: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var approvalStatus: String
    var adminRemarks: String?
    var editedData: [String: JSONValue]
    var ocrData: [String: JSONValue]
    var imageUrl: String?
    var thumbnailUrl: String?
    var originalImageUrl: String?
    var uploadedAt: Date?
    var invoiceNumber: String?
    var gstin: String?
    var vendorName: String?
    var netAmount: Double?
    var latitude: Double?
    var longitude: Double?
    var deviceId: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        approvalStatus = c.string("approvalStatus") ?? "pending"
        adminRemarks = c.string("adminRemarks")
        editedData = c.json("editedData")?.objectValue ?? [:]
        ocrData = c.json("ocrData")?.objectValue ?? [:]
        imageUrl = c.string("imageUrl")
        thumbnailUrl = c.string("thumbnailUrl")
        originalImageUrl = c.string("originalImageUrl")
        uploadedAt = c.date("uploadedAt")
        invoiceNumber = c.string("invoiceNumber")
        gstin = c.string("gstin")
        vendorName = c.string("vendorName")
        netAmount = c.double("netAmount")
        latitude = c.double("latitude")
        longitude = c.double("longitude")
        deviceId = c.string("deviceId")
    }

    private func field(_ key: String) -> JSONValue? {
        if let value = editedData[key], !value.isNull { return value }
        if let value = ocrData[key], !value.isNull { return value }
        return nil
    }

    var vendor: String { vendorName?.nilIfBlank ?? field("vendorName")?.stringValue?.nilIfBlank ?? "Unknown vendor" }
    var number: String? { invoiceNumber?.nilIfBlank ?? field("invoiceNumber")?.stringValue?.nilIfBlank }
    var gst: String? { gstin?.nilIfBlank ?? field("gstin")?.stringValue?.nilIfBlank }
    var amount: Double? { netAmount ?? field("netAmount")?.doubleValue }
    var category: String? { field("expenseCategoryName")?.stringValue?.nilIfBlank }
    var invoiceDate: Date? { DateParser.parseDay(field("invoiceDate")?.stringValue) }
    var employeeRemarks: String? { editedData["remarks"]?.stringValue?.nilIfBlank }

    /// Keys shown in the review comparison, in the same order as the employee form.
    static let fieldOrder = [
        "vendorName", "gstin", "invoiceNumber", "invoiceDate", "taxableValue", "cgst", "sgst", "igst",
        "discount", "netAmount", "expenseCategoryName", "remarks", "supplierPhone", "supplierEmail",
    ]

    static func == (lhs: AdminInvoice, rhs: AdminInvoice) -> Bool { lhs.id == rhs.id && lhs.approvalStatus == rhs.approvalStatus }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum InvoiceDecision: String, CaseIterable, Identifiable {
    case approve, reject, `return`
    var id: String { rawValue }

    var title: String {
        switch self {
        case .approve: return "Approve"
        case .reject: return "Reject"
        case .return: return "Return"
        }
    }

    var systemImage: String {
        switch self {
        case .approve: return "checkmark.seal.fill"
        case .reject: return "xmark.seal.fill"
        case .return: return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .approve: return Brand.success
        case .reject: return Brand.danger
        case .return: return Brand.orange
        }
    }

    var requiresRemarks: Bool { self != .approve }
}

// MARK: - Team & catalog

struct AdminEmployee: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var mobile: String
    var employeeCode: String
    var branchId: String?
    var branchName: String?
    var isActive: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        name = c.string("name") ?? ""
        mobile = c.string("mobile") ?? ""
        employeeCode = c.string("employeeCode") ?? ""
        branchId = c.string("branchId")
        branchName = c.string("branchName")
        isActive = c.bool("isActive") ?? true
    }
}

struct EmployeeInput: Encodable {
    var name: String
    var mobile: String
    var employeeCode: String
    var branchId: String?
    var isActive: Bool

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(name, forKey: "name")
        try c.encode(mobile, forKey: "mobile")
        try c.encode(employeeCode, forKey: "employeeCode")
        try c.encode(branchId, forKey: "branchId")
        try c.encode(isActive, forKey: "isActive")
    }
}

struct CatalogItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var code: String?
    var parentId: String?
    var sortOrder: Int
    var isActive: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        name = c.string("name") ?? ""
        code = c.string("code")
        parentId = c.string("parentId")
        sortOrder = c.int("sortOrder") ?? 0
        isActive = c.bool("isActive") ?? true
    }
}

/// `NamedResource` — PATCH replaces every field, so the full item is always sent.
struct CatalogInput: Encodable {
    var name: String
    var code: String?
    var parentId: String?
    var sortOrder: Int
    var isActive: Bool

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(name, forKey: "name")
        try c.encode(code, forKey: "code")
        try c.encode(parentId, forKey: "parentId")
        try c.encode(sortOrder, forKey: "sortOrder")
        try c.encode(isActive, forKey: "isActive")
    }
}

enum CatalogKind: String, Identifiable {
    case categories, branches
    var id: String { rawValue }
    var title: String { self == .categories ? "Categories" : "Branches" }
    var singular: String { self == .categories ? "Category" : "Branch" }
    var systemImage: String { self == .categories ? "square.grid.2x2.fill" : "building.2.fill" }
    var path: String { "/admin/company/\(rawValue)" }
}

// MARK: - Settings

struct CompanySettings: Decodable, Sendable {
    var id: String?
    var name: String
    var industry: String
    var logoUrl: String?
    var primaryColorHex: String?
    var requiresGps: Bool
    var duplicateCheckEnabled: Bool
    var minOcrConfidenceWarn: Double
    var features: [String: JSONValue]
    var status: String?
    var activationCode: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        name = c.string("name") ?? ""
        industry = c.string("industry") ?? ""
        logoUrl = c.string("logo_url", "logoUrl")
        primaryColorHex = c.string("primary_color_hex", "primaryColorHex")
        requiresGps = c.bool("requires_gps", "requiresGps") ?? false
        duplicateCheckEnabled = c.bool("duplicate_check_enabled", "duplicateCheckEnabled") ?? true
        minOcrConfidenceWarn = c.double("min_ocr_confidence_warn", "minOcrConfidenceWarn") ?? 0.55
        features = (c.json("features_json") ?? c.json("features"))?.objectValue ?? [:]
        status = c.string("status")
        activationCode = c.string("activation_code", "activationCode")
    }
}

struct CompanySettingsInput: Encodable {
    var name: String
    var industry: String
    var logoUrl: String?
    var primaryColorHex: String?
    var requiresGps: Bool
    var duplicateCheckEnabled: Bool
    var minOcrConfidenceWarn: Double
    var features: [String: JSONValue]
}

// MARK: - Notifications

struct AdminNotification: Decodable, Identifiable, Sendable {
    let id: String
    var type: String
    var title: String
    var body: String
    var createdAt: Date?
    var read: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        type = c.string("type") ?? "companyAnnouncement"
        title = c.string("title") ?? ""
        body = c.string("body") ?? ""
        createdAt = c.date("createdAt")
        read = c.bool("read") ?? false
    }
}

/// Announcements fan out to one row per employee; the admin sees one entry.
struct AnnouncementGroup: Identifiable, Decodable, Sendable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date?
    let recipients: Int
    let readCount: Int

    init(id: String, title: String, body: String, createdAt: Date?, recipients: Int, readCount: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.recipients = recipients
        self.readCount = readCount
    }

    /// `GET /admin/notifications/announcements` row.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        title = c.string("title") ?? ""
        body = c.string("body") ?? ""
        let rawCreatedAt = c.string("createdAt")
        createdAt = c.date("createdAt")
        recipients = c.int("recipients") ?? 0
        readCount = c.int("read") ?? 0
        id = "\(title)|\(body)|\(rawCreatedAt ?? "")"
    }

    static func grouping(_ items: [AdminNotification]) -> [AnnouncementGroup] {
        let announcements = items.filter { $0.type == "companyAnnouncement" }
        let grouped = Dictionary(grouping: announcements) { item in
            "\(item.title)|\(item.body)|\(item.createdAt.map { Int($0.timeIntervalSince1970 / 60) } ?? 0)"
        }
        return grouped.compactMap { key, rows in
            guard let first = rows.first else { return nil }
            return AnnouncementGroup(
                id: key,
                title: first.title,
                body: first.body,
                createdAt: rows.compactMap(\.createdAt).max(),
                recipients: rows.count,
                readCount: rows.filter(\.read).count
            )
        }
    }
}

// MARK: - ITC

enum GSTReturnType: String, CaseIterable, Identifiable {
    case gstr2b = "2B", gstr2a = "2A"
    var id: String { rawValue }
    var title: String { "GSTR-\(rawValue)" }
}

enum ITCMatchStatus: String, CaseIterable, Identifiable {
    case matched, partial, missingIn2b = "missing_in_2b", missingInBooks = "missing_in_books", mismatch
    var id: String { rawValue }

    var title: String {
        switch self {
        case .matched: return "Matched"
        case .partial: return "Partial"
        case .missingIn2b: return "Missing in 2B"
        case .missingInBooks: return "Missing in books"
        case .mismatch: return "Mismatch"
        }
    }

    var color: Color {
        switch self {
        case .matched: return Brand.success
        case .partial: return Brand.cyan
        case .missingIn2b: return Brand.orange
        case .missingInBooks: return Brand.violet
        case .mismatch: return Brand.danger
        }
    }

    var systemImage: String {
        switch self {
        case .matched: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .missingIn2b: return "doc.questionmark.fill"
        case .missingInBooks: return "book.closed.fill"
        case .mismatch: return "exclamationmark.triangle.fill"
        }
    }
}

struct ITCSummary: Decodable, Sendable {
    var counts: [String: Int]
    /// Large GSTR files are imported in the background and report `processing`.
    var status: String?
    var rowCount: Int?

    var isProcessing: Bool { status == "processing" }

    init(counts: [String: Int] = [:]) { self.counts = counts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let object = (c.json("counts") ?? c.json("matchCounts"))?.objectValue ?? [:]
        counts = object.compactMapValues { $0.doubleValue.map { Int($0) } }
        status = c.string("status")
        rowCount = c.int("rowCount")
    }

    func count(_ status: ITCMatchStatus) -> Int { counts[status.rawValue] ?? 0 }
    var total: Int { counts.values.reduce(0, +) }
}

struct ITCMatch: Decodable, Identifiable, Sendable {
    struct BookInvoice: Sendable {
        var id: String?
        var vendorName: String?
        var gstin: String?
        var invoiceNumber: String?
        var invoiceDate: Date?
        var netAmount: Double?
        var supplierPhone: String?
        var supplierEmail: String?
    }

    struct PortalRow: Sendable {
        var supplierName: String?
        var supplierGstin: String?
        var invoiceNumber: String?
        var invoiceDate: Date?
        var netAmount: Double?
    }

    let id: String
    var status: String
    var amountDelta: Double?
    var notes: String?
    var invoice: BookInvoice?
    var portalRow: PortalRow?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        status = c.string("status") ?? "matched"
        amountDelta = c.double("amountDelta")
        notes = c.string("notes")
        if let inv = c.json("invoice")?.objectValue {
            invoice = BookInvoice(
                id: inv["id"]?.stringValue,
                vendorName: inv["vendorName"]?.stringValue,
                gstin: inv["gstin"]?.stringValue,
                invoiceNumber: inv["invoiceNumber"]?.stringValue,
                invoiceDate: DateParser.parseDay(inv["invoiceDate"]?.stringValue),
                netAmount: inv["netAmount"]?.doubleValue,
                supplierPhone: inv["supplierPhone"]?.stringValue,
                supplierEmail: inv["supplierEmail"]?.stringValue
            )
        }
        if let row = c.json("portalRow")?.objectValue {
            portalRow = PortalRow(
                supplierName: row["supplierName"]?.stringValue,
                supplierGstin: row["supplierGstin"]?.stringValue,
                invoiceNumber: row["invoiceNumber"]?.stringValue,
                invoiceDate: DateParser.parseDay(row["invoiceDate"]?.stringValue),
                netAmount: row["netAmount"]?.doubleValue
            )
        }
    }

    var matchStatus: ITCMatchStatus? { ITCMatchStatus(rawValue: status) }
    var title: String { invoice?.vendorName ?? portalRow?.supplierName ?? "Unknown supplier" }
    var canRemind: Bool { invoice != nil && (matchStatus == .missingIn2b || matchStatus == .mismatch) }
}

struct ITCImport: Decodable, Identifiable, Sendable {
    let id: String
    var period: String
    var returnType: String
    var status: String
    var rowCount: Int
    var originalFilename: String?
    var errorMessage: String?
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        period = c.string("period") ?? ""
        returnType = c.string("returnType") ?? ""
        status = c.string("status") ?? ""
        rowCount = c.int("rowCount") ?? 0
        originalFilename = c.string("originalFilename")
        errorMessage = c.string("errorMessage")
        createdAt = c.date("createdAt")
    }
}

struct ITCReminderLink: Decodable, Sendable {
    var channel: String
    var status: String
    var message: String?
    var whatsappUrl: String?
    var mailtoUrl: String?
    var contactPhone: String?
    var contactEmail: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        channel = c.string("channel") ?? "manual"
        status = c.string("status") ?? ""
        message = c.string("message")
        whatsappUrl = c.string("whatsappUrl")
        mailtoUrl = c.string("mailtoUrl")
        contactPhone = c.string("contactPhone")
        contactEmail = c.string("contactEmail")
    }
}

struct ITCReminderBatch: Decodable, Sendable {
    var count: Int
    var items: [ITCReminderLink]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        count = c.int("count") ?? 0
        items = (try? c.decode([FailableDecodable<ITCReminderLink>].self, forKey: "items"))?.compactMap(\.value) ?? []
    }
}

struct ITCFollowUp: Decodable, Identifiable, Sendable {
    let id: String
    var status: String
    var channel: String
    var contactPhone: String?
    var contactEmail: String?
    var messagePreview: String?
    var called: Bool
    var promisedBy: Date?
    var createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        status = c.string("status") ?? ""
        channel = c.string("channel") ?? ""
        contactPhone = c.string("contactPhone")
        contactEmail = c.string("contactEmail")
        messagePreview = c.string("messagePreview")
        called = c.bool("called") ?? false
        promisedBy = DateParser.parseDay(c.string("promisedBy"))
        createdAt = c.date("createdAt")
    }
}

struct ITCExport: Decodable, Sendable {
    var csv: String
    var filename: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        csv = c.string("csv") ?? ""
        filename = c.string("filename") ?? "itc.csv"
    }
}

// MARK: - Activation

struct StatusResult: Decodable, Sendable {
    var status: String?
    var endsAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        status = c.string("status")
        endsAt = c.date("endsAt")
    }
}

/// Suggestions only — `industry` is free text on the server.
enum Industry {
    static let suggestions = ["Construction", "Retail", "Manufacturing", "Healthcare", "Hospitality", "Logistics", "Services", "Education", "IT"]
}
