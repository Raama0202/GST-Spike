import SwiftUI

struct InvoiceRow: View {
    let invoice: LocalInvoice

    var body: some View {
        HStack(spacing: 14) {
            InvoiceThumbnail(invoice: invoice, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(invoice.display.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(Formatters.dayString(invoice.display.invoiceDate ?? invoice.createdAt))
                    if let number = invoice.display.invoiceNumber?.nilIfBlank {
                        Text("•")
                        Text("#\(number)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if invoice.syncStatus != .uploaded {
                        StatusPill(status: invoice.syncStatus.rawValue, compact: true)
                    }
                    StatusPill(status: approvalLabel, compact: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Formatters.currency(invoice.display.netAmount))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard(cornerRadius: 22, padding: 14)
    }

    private var approvalLabel: String {
        switch invoice.approvalStatus {
        case .pending: return invoice.syncStatus == .uploaded ? "uploaded" : "pending"
        case .uploaded: return "uploaded"
        default: return invoice.approvalStatus.rawValue
        }
    }
}

/// Local thumbnail when the file is on this device, otherwise the server copy.
struct InvoiceThumbnail: View {
    let invoice: LocalInvoice
    var size: CGFloat = 58
    var preferFull = false

    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = ServerConfig.absoluteURL(preferFull ? (invoice.remoteImageUrl ?? invoice.remoteThumbnailUrl) : (invoice.remoteThumbnailUrl ?? invoice.remoteImageUrl)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    default: ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }

    private var localImage: UIImage? {
        let file = preferFull ? (invoice.compressedImageFile ?? invoice.originalImageFile) : (invoice.thumbnailFile ?? invoice.compressedImageFile)
        guard let url = TenantStorage.imageURL(companyId: invoice.companyId, file: file) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "doc.text.fill")
                .font(.system(size: size * 0.38))
                .foregroundStyle(.secondary)
        }
    }
}
