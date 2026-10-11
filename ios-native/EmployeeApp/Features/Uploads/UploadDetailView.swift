import SwiftUI

struct UploadDetailView: View {
    let localId: String

    @Environment(EmployeeContainer.self) private var container
    @Environment(SyncEngine.self) private var sync
    @Environment(ToastCenter.self) private var toasts
    @State private var invoice: LocalInvoice?
    @State private var showImage = false
    @State private var retrying = false

    var body: some View {
        ScrollView {
            if let invoice {
                VStack(spacing: 18) {
                    hero(invoice)
                    timeline(invoice)
                    if let remarks = invoice.adminRemarks?.nilIfBlank {
                        remarksCard(remarks, status: invoice.approvalStatus)
                    }
                    if invoice.syncStatus == .failed || invoice.lastUploadError != nil {
                        uploadErrorCard(invoice)
                    }
                    fieldsCard(invoice)
                }
                .padding(GlassMetrics.screenPadding)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .glassScreen()
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sync.revision) {
            invoice = await container.invoiceStore.get(localId)
        }
        .fullScreenCover(isPresented: $showImage) {
            if let invoice, let image = fullImage(invoice) {
                ZoomableImageView(image: image)
            }
        }
    }

    // MARK: - Sections

    private func hero(_ invoice: LocalInvoice) -> some View {
        VStack(spacing: 16) {
            Button { showImage = fullImage(invoice) != nil } label: {
                InvoiceThumbnail(invoice: invoice, size: 120, preferFull: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            VStack(spacing: 6) {
                Text(invoice.display.displayTitle)
                    .font(.display(22, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(Formatters.currency(invoice.display.netAmount))
                    .font(.display(34, weight: .heavy))
                HStack(spacing: 8) {
                    StatusPill(status: invoice.syncStatus.rawValue)
                    StatusPill(status: invoice.approvalStatus == .pending && invoice.syncStatus == .uploaded ? "uploaded" : invoice.approvalStatus.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    private func timeline(_ invoice: LocalInvoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineStep(title: "Captured", subtitle: Formatters.dayTime.string(from: invoice.createdAt), state: .done, isLast: false)
            TimelineStep(
                title: invoice.syncStatus == .uploaded ? "Uploaded to dashboard" : "Waiting to upload",
                subtitle: invoice.uploadedAt.map { Formatters.dayTime.string(from: $0) } ?? (invoice.syncStatus == .failed ? "Upload failed" : "Will retry automatically"),
                state: invoice.syncStatus == .uploaded ? .done : (invoice.syncStatus == .failed ? .failed : .active),
                isLast: false
            )
            TimelineStep(
                title: decisionTitle(invoice.approvalStatus),
                subtitle: invoice.syncStatus == .uploaded ? decisionSubtitle(invoice.approvalStatus) : "After upload",
                state: decisionState(invoice),
                isLast: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func remarksCard(_ remarks: String, status: ApprovalStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Admin remarks", systemImage: "text.bubble.fill")
                .font(.headline)
                .foregroundStyle(StatusPill.style(for: status.rawValue).color)
            Text(remarks).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: StatusPill.style(for: status.rawValue).color)
    }

    private func uploadErrorCard(_ invoice: LocalInvoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upload problem", systemImage: "exclamationmark.icloud.fill")
                .font(.headline)
                .foregroundStyle(Brand.danger)
            if let error = invoice.lastUploadError {
                Text(error).font(.subheadline)
            }
            Text("Attempts: \(invoice.uploadAttempts)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if invoice.syncStatus == .failed {
                Button {
                    Task {
                        retrying = true
                        await sync.retry(invoice.localId)
                        retrying = false
                        toasts.show("Retrying upload…")
                    }
                } label: {
                    LoadingLabel(title: "Retry upload", systemImage: "arrow.clockwise", isLoading: retrying)
                }
                .buttonStyle(.glassPrimary)
                .disabled(retrying)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Brand.danger)
    }

    private func fieldsCard(_ invoice: LocalInvoice) -> some View {
        let d = invoice.display
        let o = invoice.ocrData
        let money: (Double?) -> String? = { value in value.map { Formatters.currency($0) } }
        let date: (Date?) -> String? = { value in value.map { Formatters.dayString($0) } }
        return VStack(alignment: .leading, spacing: 12) {
            Label("Invoice details", systemImage: "list.bullet.rectangle.portrait.fill")
                .font(.headline)
            fieldRow("Vendor", d.vendorName, o.vendorName)
            fieldRow("GSTIN", d.gstin, o.gstin)
            fieldRow("Invoice #", d.invoiceNumber, o.invoiceNumber)
            fieldRow("Date", date(d.invoiceDate), date(o.invoiceDate))
            GlassDivider()
            fieldRow("Taxable", money(d.taxableValue), money(o.taxableValue))
            fieldRow("CGST", money(d.cgst), money(o.cgst))
            fieldRow("SGST", money(d.sgst), money(o.sgst))
            fieldRow("IGST", money(d.igst), money(o.igst))
            fieldRow("Discount", money(d.discount), money(o.discount))
            fieldRow("Net amount", money(d.netAmount), money(o.netAmount))
            GlassDivider()
            fieldRow("Category", d.expenseCategoryName, nil)
            fieldRow("Remarks", d.remarks, nil)
            if invoice.ocrConfidence > 0 {
                DetailRow(label: "OCR confidence", value: "\(Int((invoice.ocrConfidence * 100).rounded()))%")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Shows the submitted value and, when the employee corrected OCR, the original.
    @ViewBuilder
    private func fieldRow(_ label: String, _ value: String?, _ ocrValue: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            DetailRow(label: label, value: value ?? "—")
            if let ocrValue, ocrValue != value {
                Text("OCR: \(ocrValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
        }
    }

    private func fullImage(_ invoice: LocalInvoice) -> UIImage? {
        let file = invoice.compressedImageFile ?? invoice.originalImageFile
        guard let url = TenantStorage.imageURL(companyId: invoice.companyId, file: file) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func decisionTitle(_ status: ApprovalStatus) -> String {
        switch status {
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .returned: return "Returned for correction"
        default: return "Admin review"
        }
    }

    private func decisionSubtitle(_ status: ApprovalStatus) -> String {
        switch status {
        case .approved: return "Ready for reimbursement"
        case .rejected: return "See remarks below"
        case .returned: return "Update and resubmit"
        default: return "Waiting for your admin"
        }
    }

    private func decisionState(_ invoice: LocalInvoice) -> TimelineStep.StepState {
        guard invoice.syncStatus == .uploaded else { return .upcoming }
        switch invoice.approvalStatus {
        case .approved: return .done
        case .rejected, .returned: return .failed
        default: return .active
        }
    }
}

struct TimelineStep: View {
    enum StepState { case done, active, failed, upcoming }
    let title: String
    let subtitle: String
    let state: StepState
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(color.opacity(0.2)).frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }
                if !isLast {
                    Rectangle()
                        .fill(color.opacity(0.35))
                        .frame(width: 2, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 5)
        }
    }

    private var color: Color {
        switch state {
        case .done: return Brand.success
        case .active: return Brand.primary
        case .failed: return Brand.danger
        case .upcoming: return .gray
        }
    }

    private var icon: String {
        switch state {
        case .done: return "checkmark"
        case .active: return "clock"
        case .failed: return "exclamationmark"
        case .upcoming: return "circle.dotted"
        }
    }
}
