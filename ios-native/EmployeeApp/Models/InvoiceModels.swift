import Foundation

enum SyncStatus: String, Codable, Sendable {
    case pending, uploading, uploaded, failed
}

enum ApprovalStatus: String, Codable, Sendable {
    case pending, uploaded, approved, rejected, returned

    init(apiValue: String?) {
        self = ApprovalStatus(rawValue: (apiValue ?? "").lowercased()) ?? .pending
    }
}

/// Field set shared by `ocrData` and `editedData`. Keys and encoding match
/// the Android `InvoiceFieldData.toJson()` so the dashboard sees identical
/// payloads from both platforms.
struct InvoiceFields: Codable, Hashable, Sendable {
    var vendorName: String?
    var gstin: String?
    var invoiceNumber: String?
    var invoiceDate: Date?
    var taxableValue: Double?
    var cgst: Double?
    var sgst: Double?
    var igst: Double?
    var discount: Double?
    var netAmount: Double?
    var expenseCategoryId: String?
    var expenseCategoryName: String?
    var remarks: String?
    var supplierPhone: String?
    var supplierEmail: String?

    init(
        vendorName: String? = nil, gstin: String? = nil, invoiceNumber: String? = nil, invoiceDate: Date? = nil,
        taxableValue: Double? = nil, cgst: Double? = nil, sgst: Double? = nil, igst: Double? = nil,
        discount: Double? = nil, netAmount: Double? = nil, expenseCategoryId: String? = nil,
        expenseCategoryName: String? = nil, remarks: String? = nil, supplierPhone: String? = nil, supplierEmail: String? = nil
    ) {
        self.vendorName = vendorName
        self.gstin = gstin
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.taxableValue = taxableValue
        self.cgst = cgst
        self.sgst = sgst
        self.igst = igst
        self.discount = discount
        self.netAmount = netAmount
        self.expenseCategoryId = expenseCategoryId
        self.expenseCategoryName = expenseCategoryName
        self.remarks = remarks
        self.supplierPhone = supplierPhone
        self.supplierEmail = supplierEmail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        vendorName = c.string("vendorName", "vendor_name")
        gstin = c.string("gstin")
        invoiceNumber = c.string("invoiceNumber", "invoice_number")
        invoiceDate = c.string("invoiceDate", "invoice_date").flatMap { DateParser.parseDay($0) }
        taxableValue = c.double("taxableValue", "taxableAmount", "taxable_amount")
        cgst = c.double("cgst", "cgstAmount")
        sgst = c.double("sgst", "sgstAmount")
        igst = c.double("igst", "igstAmount")
        discount = c.double("discount")
        netAmount = c.double("netAmount", "net_amount", "totalAmount")
        expenseCategoryId = c.string("expenseCategoryId")
        expenseCategoryName = c.string("expenseCategoryName")
        remarks = c.string("remarks")
        supplierPhone = c.string("supplierPhone")
        supplierEmail = c.string("supplierEmail")
    }

    /// Nulls are written explicitly, exactly like the Dart client.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(vendorName, forKey: "vendorName")
        try c.encode(gstin, forKey: "gstin")
        try c.encode(invoiceNumber, forKey: "invoiceNumber")
        try c.encode(invoiceDate.map(Self.isoLocal), forKey: "invoiceDate")
        try c.encode(taxableValue, forKey: "taxableValue")
        try c.encode(cgst, forKey: "cgst")
        try c.encode(sgst, forKey: "sgst")
        try c.encode(igst, forKey: "igst")
        try c.encode(discount, forKey: "discount")
        try c.encode(netAmount, forKey: "netAmount")
        try c.encode(expenseCategoryId, forKey: "expenseCategoryId")
        try c.encode(expenseCategoryName, forKey: "expenseCategoryName")
        try c.encode(remarks, forKey: "remarks")
        try c.encode(supplierPhone, forKey: "supplierPhone")
        try c.encode(supplierEmail, forKey: "supplierEmail")
    }

    /// Dart's `DateTime.toIso8601String()` for a local calendar date, which the
    /// backend parses with `datetime.fromisoformat`.
    private static func isoLocal(_ date: Date) -> String {
        DateParser.dayString(date) + "T00:00:00.000"
    }

    var totalTax: Double? {
        let parts = [cgst, sgst, igst].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    var displayTitle: String {
        vendorName?.nilIfBlank ?? invoiceNumber?.nilIfBlank ?? "Invoice"
    }
}

/// An invoice captured on this device (or pulled from `/invoices/mine`).
/// Image paths are stored as file names relative to the tenant folder because
/// the iOS container path changes between app updates.
struct LocalInvoice: Codable, Identifiable, Hashable, Sendable {
    var localId: String
    var serverId: String?
    var companyId: String
    var employeeId: String
    var branchId: String?
    var deviceId: String
    var createdAt: Date
    var uploadedAt: Date?
    var syncStatus: SyncStatus
    var approvalStatus: ApprovalStatus
    var ocrData: InvoiceFields
    var editedData: InvoiceFields
    var ocrConfidence: Double
    var originalImageFile: String?
    var compressedImageFile: String?
    var thumbnailFile: String?
    var remoteImageUrl: String?
    var remoteThumbnailUrl: String?
    var latitude: Double?
    var longitude: Double?
    var uploadAttempts: Int = 0
    var lastUploadError: String?
    var idempotencyKey: String?
    var adminRemarks: String?
    var duplicateOverride: Bool = false
    var isQueued: Bool = false
    var nextAttemptAt: Date?

    var id: String { localId }
    var display: InvoiceFields { editedData }

    var needsUpload: Bool {
        isQueued && (syncStatus == .pending || syncStatus == .uploading)
    }
}

/// Row from `GET /invoices/mine`.
struct RemoteInvoiceSummary: Decodable, Sendable {
    let id: String
    let localIdempotencyKey: String?
    let approvalStatus: String?
    let adminRemarks: String?
    let editedData: InvoiceFields?
    let ocrData: InvoiceFields?
    let imageUrl: String?
    let thumbnailUrl: String?
    let uploadedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        localIdempotencyKey = c.string("localIdempotencyKey")
        approvalStatus = c.string("approvalStatus", "status")
        adminRemarks = c.string("adminRemarks")
        editedData = try? c.decodeIfPresent(InvoiceFields.self, forKey: "editedData")
        ocrData = try? c.decodeIfPresent(InvoiceFields.self, forKey: "ocrData")
        imageUrl = c.string("imageUrl")
        thumbnailUrl = c.string("thumbnailUrl")
        uploadedAt = c.date("uploadedAt")
    }
}

struct UploadResponse: Decodable {
    let id: String
    let approvalStatus: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id", "serverId", "invoiceId"), !id.isEmpty else {
            throw APIError(kind: .decoding, status: nil, message: "Upload succeeded but server id was missing.")
        }
        self.id = id
        approvalStatus = c.string("approvalStatus")
    }
}

struct DuplicateCheckResult: Sendable {
    let isDuplicate: Bool
    let message: String?
}

/// Result of OCR / AI extraction.
struct ExtractionResult: Sendable {
    enum Source: String, Sendable { case ai, onDevice }
    let fields: InvoiceFields
    let confidence: Double
    let rawText: String
    let source: Source
}
