import Foundation

/// Durable offline store for invoices and their upload-queue state.
/// "Submit never requires network": rows are persisted first, then queued.
actor InvoiceStore {
    private var companyId: String?
    private var invoices: [String: LocalInvoice] = [:]

    private var fileURL: URL? {
        companyId.map { TenantStorage.directory($0).appendingPathComponent("invoices.json") }
    }

    func open(companyId: String?) {
        guard self.companyId != companyId else { return }
        self.companyId = companyId
        invoices = [:]
        guard let url = fileURL, let stored = TenantStorage.read([LocalInvoice].self, from: url) else { return }
        invoices = Dictionary(stored.map { ($0.localId, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func all() -> [LocalInvoice] {
        invoices.values.sorted { $0.createdAt > $1.createdAt }
    }

    func get(_ localId: String) -> LocalInvoice? {
        invoices[localId]
    }

    func save(_ invoice: LocalInvoice) {
        invoices[invoice.localId] = invoice
        persist()
    }

    func delete(_ localId: String) {
        guard let invoice = invoices.removeValue(forKey: localId) else { return }
        if let companyId {
            for file in [invoice.originalImageFile, invoice.compressedImageFile, invoice.thumbnailFile] {
                if let url = TenantStorage.imageURL(companyId: companyId, file: file) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        persist()
    }

    /// Items that the sync engine should attempt, oldest first.
    func queued() -> [LocalInvoice] {
        invoices.values.filter(\.needsUpload).sorted { $0.createdAt < $1.createdAt }
    }

    func pendingCount() -> Int {
        invoices.values.filter { $0.isQueued && $0.syncStatus != .uploaded }.count
    }

    func todayCount() -> Int {
        let calendar = Calendar.current
        return invoices.values.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    /// Uploads interrupted by the app being killed are put back in the queue.
    func recoverStuckUploads() {
        var changed = false
        for (id, invoice) in invoices where invoice.syncStatus == .uploading {
            var updated = invoice
            updated.syncStatus = .pending
            updated.lastUploadError = nil
            invoices[id] = updated
            changed = true
        }
        if changed { persist() }
    }

    func findLocalDuplicate(gstin: String?, invoiceNumber: String?, excluding localId: String?) -> LocalInvoice? {
        guard let number = invoiceNumber?.nilIfBlank?.lowercased() else { return nil }
        let gst = gstin?.nilIfBlank?.uppercased()
        return invoices.values.first { invoice in
            guard invoice.localId != localId,
                  invoice.editedData.invoiceNumber?.lowercased() == number
            else { return false }
            guard let gst else { return true }
            return invoice.editedData.gstin?.uppercased() == gst
        }
    }

    /// Applies `GET /invoices/mine` so admin decisions show up in My Uploads
    /// even when the notification was missed.
    @discardableResult
    func merge(remote items: [RemoteInvoiceSummary], employee: Employee) -> Int {
        var changes = 0
        for item in items {
            let status = ApprovalStatus(apiValue: item.approvalStatus)
            let match = invoices.values.first { local in
                local.serverId == item.id || (item.localIdempotencyKey != nil && (local.idempotencyKey ?? local.localId) == item.localIdempotencyKey)
            }
            if var local = match {
                let mapped: ApprovalStatus = status == .pending ? .uploaded : status
                if local.approvalStatus != mapped || local.adminRemarks != item.adminRemarks || local.serverId != item.id {
                    changes += 1
                }
                local.serverId = item.id
                local.approvalStatus = mapped
                local.adminRemarks = item.adminRemarks
                local.syncStatus = .uploaded
                local.isQueued = false
                local.remoteImageUrl = item.imageUrl ?? local.remoteImageUrl
                local.remoteThumbnailUrl = item.thumbnailUrl ?? local.remoteThumbnailUrl
                local.uploadedAt = local.uploadedAt ?? item.uploadedAt
                invoices[local.localId] = local
            } else {
                let localId = item.localIdempotencyKey ?? item.id
                let fields = item.editedData ?? item.ocrData ?? InvoiceFields()
                invoices[localId] = LocalInvoice(
                    localId: localId,
                    serverId: item.id,
                    companyId: employee.companyId,
                    employeeId: employee.id,
                    branchId: employee.branchId,
                    deviceId: "",
                    createdAt: item.uploadedAt ?? Date(),
                    uploadedAt: item.uploadedAt,
                    syncStatus: .uploaded,
                    approvalStatus: status == .pending ? .uploaded : status,
                    ocrData: item.ocrData ?? fields,
                    editedData: fields,
                    ocrConfidence: 0,
                    remoteImageUrl: item.imageUrl,
                    remoteThumbnailUrl: item.thumbnailUrl,
                    idempotencyKey: item.localIdempotencyKey,
                    adminRemarks: item.adminRemarks
                )
                changes += 1
            }
        }
        if changes > 0 { persist() }
        return changes
    }

    // MARK: - Images

    func writeImage(_ data: Data, name: String) throws -> String {
        guard let companyId else {
            throw APIError(kind: .unknown, status: nil, message: "No active company session.")
        }
        let url = TenantStorage.imagesDirectory(companyId).appendingPathComponent(name)
        try TenantStorage.write(data, to: url)
        return name
    }

    func imageData(_ file: String?) -> Data? {
        guard let companyId, let url = TenantStorage.imageURL(companyId: companyId, file: file) else { return nil }
        return try? Data(contentsOf: url)
    }

    func wipe() {
        if let companyId { TenantStorage.wipe(companyId) }
        invoices = [:]
    }

    private func persist() {
        guard let url = fileURL else { return }
        TenantStorage.save(Array(invoices.values), to: url)
    }
}
