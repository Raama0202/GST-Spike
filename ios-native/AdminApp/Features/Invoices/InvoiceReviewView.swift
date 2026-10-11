import SwiftUI
import MapKit

struct InvoiceReviewView: View {
    let invoiceId: String
    var onDecision: (AdminInvoice) -> Void = { _ in }

    @Environment(AdminSession.self) private var session
    @Environment(AdminWorkspace.self) private var workspace
    @Environment(ToastCenter.self) private var toasts

    @State private var invoice: AdminInvoice?
    @State private var error: String?
    @State private var pendingDecision: InvoiceDecision?
    @State private var remarks = ""
    @State private var isSubmitting = false
    @State private var showImage = false

    var body: some View {
        ScrollView {
            if let invoice {
                VStack(spacing: 18) {
                    imageCard(invoice)
                    summaryCard(invoice)
                    if let remarks = invoice.adminRemarks?.nilIfBlank {
                        InfoBanner(message: "Admin remarks: \(remarks)", systemImage: "text.bubble.fill", color: StatusPill.style(for: invoice.approvalStatus).color)
                    }
                    fieldsCard(invoice)
                    if let lat = invoice.latitude, let lon = invoice.longitude {
                        locationCard(lat: lat, lon: lon)
                    }
                }
                .padding(GlassMetrics.screenPadding)
                .padding(.bottom, 110)
            } else if let error {
                ErrorBanner(message: error) { Task { await load() } }
                    .padding(GlassMetrics.screenPadding)
            } else {
                ProgressView().padding(.top, 100)
            }
        }
        .glassScreen()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if invoice != nil { decisionBar }
        }
        .sheet(item: $pendingDecision) { decision in
            DecisionSheet(decision: decision, remarks: $remarks, isSubmitting: isSubmitting) {
                Task { await decide(decision) }
            }
            .presentationDetents([.height(decision.requiresRemarks ? 360 : 300)])
        }
        .fullScreenCover(isPresented: $showImage) {
            RemoteImageViewer(path: invoice?.originalImageUrl ?? invoice?.imageUrl)
        }
        .task { await load() }
    }

    // MARK: - Sections

    private func imageCard(_ invoice: AdminInvoice) -> some View {
        Button { showImage = true } label: {
            RemoteImage(path: invoice.imageUrl ?? invoice.thumbnailUrl)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Tap to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                }
                .overlay(RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func summaryCard(_ invoice: AdminInvoice) -> some View {
        VStack(spacing: 10) {
            StatusPill(status: invoice.approvalStatus)
            Text(invoice.vendor)
                .font(.display(22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(Formatters.currency(invoice.amount))
                .font(.display(36, weight: .heavy))
            HStack(spacing: 14) {
                if let number = invoice.number {
                    Label(number, systemImage: "number")
                }
                if let date = invoice.invoiceDate {
                    Label(Formatters.dayString(date), systemImage: "calendar")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let uploaded = invoice.uploadedAt {
                Text("Uploaded \(Formatters.dayTime.string(from: uploaded))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    private func fieldsCard(_ invoice: AdminInvoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Extracted vs submitted", subtitle: "Employee corrections are highlighted")
            ForEach(AdminInvoice.fieldOrder, id: \.self) { key in
                let edited = invoice.editedData[key]
                let ocr = invoice.ocrData[key]
                if (edited.map { !$0.isNull } ?? false) || (ocr.map { !$0.isNull } ?? false) {
                    let changed = (edited ?? .null) != (ocr ?? .null) && ocr != nil && !(ocr?.isNull ?? true)
                    VStack(alignment: .trailing, spacing: 2) {
                        DetailRow(
                            label: key.humanizedKey,
                            value: format(key, edited ?? ocr ?? .null),
                            valueColor: changed ? Brand.orange : .primary
                        )
                        if changed, let ocr {
                            Text("OCR: \(format(key, ocr))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                    }
                }
            }
            if let device = invoice.deviceId?.nilIfBlank {
                GlassDivider()
                DetailRow(label: "Device", value: String(device.prefix(12)), systemImage: "iphone")
            }
        }
        .glassCard()
    }

    private func locationCard(lat: Double, lon: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Capture location")
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                Marker("Invoice", systemImage: "doc.text.fill", coordinate: coordinate)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous))
            .allowsHitTesting(false)
        }
        .glassCard()
    }

    private var decisionBar: some View {
        HStack(spacing: 10) {
            ForEach(InvoiceDecision.allCases) { decision in
                Button {
                    remarks = ""
                    pendingDecision = decision
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: decision.systemImage).font(.title3)
                        Text(decision.title).font(.caption.weight(.bold))
                    }
                    .foregroundStyle(decision == .approve ? .white : decision.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if decision == .approve {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(decision.color.gradient)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(decision.color.opacity(0.14))
                        }
                    }
                }
                .buttonStyle(AdminPressableStyle())
                .disabled(invoice?.approvalStatus == statusValue(decision))
                .opacity(invoice?.approvalStatus == statusValue(decision) ? 0.4 : 1)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(.horizontal, GlassMetrics.screenPadding)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func statusValue(_ decision: InvoiceDecision) -> String {
        switch decision {
        case .approve: return "approved"
        case .reject: return "rejected"
        case .return: return "returned"
        }
    }

    private func format(_ key: String, _ value: JSONValue) -> String {
        if key == "invoiceDate", let date = DateParser.parseDay(value.stringValue) {
            return Formatters.dayString(date)
        }
        if ["taxableValue", "cgst", "sgst", "igst", "discount", "netAmount"].contains(key), let amount = value.doubleValue {
            return Formatters.currency(amount)
        }
        return value.displayText
    }

    private func load() async {
        do {
            invoice = try await session.api.invoice(invoiceId)
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
    }

    private func decide(_ decision: InvoiceDecision) async {
        let note = remarks.nilIfBlank
        if decision.requiresRemarks && note == nil { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let updated = try await session.api.decide(invoiceId, decision: decision, remarks: note)
            var merged = updated
            merged.originalImageUrl = invoice?.originalImageUrl
            merged.latitude = invoice?.latitude
            merged.longitude = invoice?.longitude
            merged.deviceId = invoice?.deviceId
            invoice = merged
            pendingDecision = nil
            onDecision(updated)
            toasts.success("Invoice \(statusValue(decision)) — employee notified")
            await workspace.refreshStats()
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }
}

private struct DecisionSheet: View {
    let decision: InvoiceDecision
    @Binding var remarks: String
    let isSubmitting: Bool
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            IconBadge(systemImage: decision.systemImage, color: decision.color, size: 54)
            Text("\(decision.title) invoice")
                .font(.display(22, weight: .bold))
            GlassTextField(
                title: decision.requiresRemarks ? "Remarks (required)" : "Remarks (optional)",
                text: $remarks,
                systemImage: "text.bubble",
                prompt: decision == .return ? "What should the employee fix?" : "Visible to the employee",
                axis: .vertical
            )
            Button(action: onConfirm) {
                LoadingLabel(title: "Confirm \(decision.title.lowercased())", systemImage: decision.systemImage, isLoading: isSubmitting)
            }
            .buttonStyle(.glassPrimary)
            .tint(decision.color)
            .disabled(isSubmitting || (decision.requiresRemarks && remarks.nilIfBlank == nil))
        }
        .padding(GlassMetrics.screenPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBackground())
        .brand(decision.color)
    }
}

struct RemoteImageViewer: View {
    let path: String?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(path: path, contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, min(lastScale * $0, 5)) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
    }
}
