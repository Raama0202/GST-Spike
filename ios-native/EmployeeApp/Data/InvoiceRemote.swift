import Foundation

/// Invoice endpoints. Payload shape is identical to the Android
/// `InvoiceRemoteDataSource` so the dashboard cannot tell the platforms apart.
struct InvoiceRemote: Sendable {
    let api: APIClient

    func checkDuplicate(_ fields: InvoiceFields) async throws -> DuplicateCheckResult {
        guard let number = fields.invoiceNumber?.nilIfBlank else {
            return DuplicateCheckResult(isDuplicate: false, message: nil)
        }
        struct Body: Encodable {
            let invoiceNumber: String
            let gstin: String?
            let invoiceDate: String?
            let netAmount: Double?
        }
        struct Response: Decodable {
            let isDuplicate: Bool
            let message: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                isDuplicate = c.bool("isDuplicate", "duplicate") ?? false
                message = c.string("message")
            }
        }
        let body = Body(
            invoiceNumber: number,
            gstin: fields.gstin?.nilIfBlank,
            invoiceDate: fields.invoiceDate.map(DateParser.dayString),
            netAmount: fields.netAmount
        )
        let response: Response = try await api.send(.post, EmployeeEndpoints.duplicateCheck, json: body)
        return DuplicateCheckResult(isDuplicate: response.isDuplicate, message: response.message)
    }

    func upload(_ invoice: LocalInvoice, original: Data, compressed: Data, thumbnail: Data) async throws -> UploadResponse {
        let payload = UploadPayload(invoice: invoice)
        let payloadJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"

        var form = MultipartForm()
        form.addField("idempotencyKey", invoice.idempotencyKey ?? invoice.localId)
        form.addField("payload", payloadJSON)
        form.addFile("original", filename: "original.jpg", mimeType: "image/jpeg", data: original)
        form.addFile("compressed", filename: "compressed.jpg", mimeType: "image/jpeg", data: compressed)
        form.addFile("thumbnail", filename: "thumbnail.jpg", mimeType: "image/jpeg", data: thumbnail)
        return try await api.upload(EmployeeEndpoints.upload, form: form)
    }

    func mine(page: Int = 1, pageSize: Int = 100) async throws -> [RemoteInvoiceSummary] {
        let response: ItemsResponse<RemoteInvoiceSummary> = try await api.get(
            EmployeeEndpoints.mine,
            query: ["page": String(page), "pageSize": String(pageSize)]
        )
        return response.items
    }
}

/// Matches the API's `InvoicePayload`; identifiers the server rejects when
/// blank or non-UUID are omitted rather than sent empty.
private struct UploadPayload: Encodable {
    let invoice: LocalInvoice

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeIfPresent(Self.uuidOrNil(invoice.branchId), forKey: "branchId")
        let category = Self.uuidOrNil(invoice.editedData.expenseCategoryId) ?? Self.uuidOrNil(invoice.ocrData.expenseCategoryId)
        try c.encodeIfPresent(category, forKey: "categoryId")
        if !invoice.deviceId.isEmpty { try c.encode(invoice.deviceId, forKey: "deviceId") }
        try c.encodeIfPresent(invoice.latitude, forKey: "latitude")
        try c.encodeIfPresent(invoice.longitude, forKey: "longitude")
        try c.encode(invoice.ocrConfidence, forKey: "ocrConfidence")
        try c.encode(invoice.ocrData, forKey: "ocrData")
        try c.encode(invoice.editedData, forKey: "editedData")
        try c.encode(invoice.duplicateOverride, forKey: "duplicateOverride")
    }

    private static func uuidOrNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty, UUID(uuidString: value) != nil else { return nil }
        return value
    }
}
