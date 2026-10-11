import CoreLocation
import SwiftUI

/// Review + submit. Mirrors the Android review screen: low-confidence fields
/// are highlighted (never blocking), duplicates warn before submit, and submit
/// persists locally first so it never needs the network.
struct ReviewView: View {
    let draft: ScanDraft
    var onRetake: () -> Void
    var onSubmitted: () -> Void

    @Environment(EmployeeContainer.self) private var container
    @Environment(SessionModel.self) private var session
    @Environment(CompanyConfigModel.self) private var config
    @Environment(SyncEngine.self) private var sync
    @Environment(ToastCenter.self) private var toasts

    @State private var vendor = ""
    @State private var gstin = ""
    @State private var invoiceNumber = ""
    @State private var invoiceDate = Date()
    @State private var hasDate = false
    @State private var taxable = ""
    @State private var cgst = ""
    @State private var sgst = ""
    @State private var igst = ""
    @State private var discount = ""
    @State private var net = ""
    @State private var category = ""
    @State private var remarks = ""

    @State private var isSubmitting = false
    @State private var error: String?
    @State private var duplicateMessage: String?
    @State private var showDuplicateDialog = false
    @State private var duplicateOverride = false
    @State private var showImage = false
    @State private var loaded = false

    private var ocr: InvoiceFields { draft.extraction.fields }
    private var lowConfidence: Bool {
        draft.extraction.confidence < (config.config?.minOcrConfidenceWarn ?? EmployeeConstants.lowOcrConfidenceThreshold)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                imageCard
                banners
                supplierSection
                amountsSection
                classificationSection
                actions
            }
            .padding(GlassMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .glassScreen()
        .navigationTitle("Review invoice")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSubmitting)
        .overlay { LoadingOverlay(isVisible: isSubmitting, message: "Saving invoice…") }
        .confirmationDialog("Possible duplicate", isPresented: $showDuplicateDialog, titleVisibility: .visible) {
            Button("Submit anyway") {
                duplicateOverride = true
                Task { await submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(duplicateMessage ?? "An invoice with the same GSTIN and number may already exist.")
        }
        .fullScreenCover(isPresented: $showImage) {
            ZoomableImageView(image: draft.preview)
        }
        .onAppear(perform: loadDraft)
    }

    // MARK: - Sections

    private var imageCard: some View {
        HStack(spacing: 16) {
            Button { showImage = true } label: {
                Image(uiImage: draft.preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 104, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(6)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                ConfidenceRing(value: draft.extraction.confidence, isLow: lowConfidence)
                Label(
                    draft.extraction.source == .ai ? "AI extracted" : "On-device OCR",
                    systemImage: draft.extraction.source == .ai ? "sparkles" : "cpu"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(draft.extraction.source == .ai ? Brand.violet : Brand.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((draft.extraction.source == .ai ? Brand.violet : Brand.cyan).opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }

    @ViewBuilder
    private var banners: some View {
        if let extractionError = draft.extractionError {
            InfoBanner(message: extractionError, systemImage: "text.badge.xmark", color: Brand.orange)
        } else if lowConfidence {
            InfoBanner(message: "Low OCR confidence — please verify the highlighted fields.", systemImage: "exclamationmark.triangle.fill")
        }
        if draft.isBlurry {
            InfoBanner(message: "The photo looks blurry. Retake it if the amounts are hard to read.", systemImage: "camera.metering.unknown", color: Brand.orange)
        }
        if let error {
            ErrorBanner(message: error)
        }
    }

    private var supplierSection: some View {
        FormSection(title: "Supplier", systemImage: "building.2.fill") {
            GlassTextField(title: "Vendor name", text: $vendor, systemImage: "storefront", prompt: "Seller business name", highlight: ocr.vendorName == nil)
            GlassTextField(title: "GSTIN", text: $gstin, systemImage: "number", prompt: "15-character GSTIN", capitalization: .characters, highlight: ocr.gstin == nil)
            if let gstinWarning {
                Text(gstinWarning)
                    .font(.caption)
                    .foregroundStyle(Brand.warning)
                    .padding(.leading, 4)
            }
            GlassTextField(title: "Invoice number", text: $invoiceNumber, systemImage: "doc.text", prompt: "INV-001", capitalization: .characters, highlight: ocr.invoiceNumber == nil)

            VStack(alignment: .leading, spacing: 6) {
                Text("Invoice date")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                HStack {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    if hasDate {
                        DatePicker("", selection: $invoiceDate, in: earliestDate...Date().addingTimeInterval(86_400), displayedComponents: .date)
                            .labelsHidden()
                        Spacer()
                        Button { hasDate = false } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Select date") { hasDate = true }
                            .font(.body.weight(.medium))
                        Spacer()
                        if ocr.invoiceDate == nil {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
        }
    }

    private var amountsSection: some View {
        FormSection(title: "Amounts", systemImage: "indianrupeesign.circle.fill") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                amountField("Taxable value", $taxable)
                amountField("Discount", $discount)
                amountField("CGST", $cgst)
                amountField("SGST", $sgst)
                amountField("IGST", $igst)
            }
            GlassTextField(title: "Net amount", text: $net, systemImage: "indianrupeesign", prompt: "0.00", keyboard: .decimalPad, highlight: ocr.netAmount == nil)
            if let calculated = calculatedNet, Formatters.parseAmount(net).map({ abs($0 - calculated) > 1 }) ?? true {
                Button {
                    net = Formatters.amountText(calculated)
                } label: {
                    Label("Use calculated total \(Formatters.currency(calculated))", systemImage: "function")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.leading, 4)
            }
        }
    }

    private var classificationSection: some View {
        FormSection(title: "Classification", systemImage: "tag.fill") {
            GlassTextField(title: "Category", text: $category, systemImage: "square.grid.2x2", prompt: "Type any category name")
            if !config.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(config.categories.prefix(12)) { item in
                            GlassChip(title: item.name, isSelected: category.caseInsensitiveCompare(item.name) == .orderedSame) {
                                category = item.name
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            GlassTextField(
                title: (config.config?.remarksRequired ?? false) ? "Remarks (required)" : "Remarks",
                text: $remarks,
                systemImage: "text.bubble",
                prompt: "Optional note for your admin",
                axis: .vertical
            )
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await submit() }
            } label: {
                LoadingLabel(title: "Submit invoice", systemImage: "paperplane.fill", isLoading: isSubmitting)
            }
            .buttonStyle(.glassPrimary)
            .disabled(isSubmitting)

            Button {
                onRetake()
            } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.glassSecondary)
            .disabled(isSubmitting)
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func amountField(_ title: String, _ binding: Binding<String>) -> some View {
        GlassTextField(title: title, text: binding, prompt: "0.00", keyboard: .decimalPad)
    }

    // MARK: - Derived

    private var earliestDate: Date {
        Calendar.current.date(from: DateComponents(year: 2017, month: 7, day: 1)) ?? .distantPast
    }

    private var gstinWarning: String? {
        let value = gstin.trimmingCharacters(in: .whitespaces).uppercased()
        guard !value.isEmpty else { return nil }
        let pattern = #"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$"#
        return value.range(of: pattern, options: .regularExpression) == nil ? "This doesn't look like a valid GSTIN." : nil
    }

    private var calculatedNet: Double? {
        guard let base = Formatters.parseAmount(taxable) else { return nil }
        let taxes = [cgst, sgst, igst].compactMap(Formatters.parseAmount).reduce(0, +)
        let value = base + taxes - (Formatters.parseAmount(discount) ?? 0)
        return value > 0 ? value : nil
    }

    // MARK: - Actions

    private func loadDraft() {
        guard !loaded else { return }
        loaded = true
        vendor = ocr.vendorName ?? ""
        gstin = ocr.gstin ?? ""
        invoiceNumber = ocr.invoiceNumber ?? ""
        if let date = ocr.invoiceDate {
            invoiceDate = date
            hasDate = true
        }
        taxable = Formatters.amountText(ocr.taxableValue)
        cgst = Formatters.amountText(ocr.cgst)
        sgst = Formatters.amountText(ocr.sgst)
        igst = Formatters.amountText(ocr.igst)
        discount = Formatters.amountText(ocr.discount)
        net = Formatters.amountText(ocr.netAmount)
    }

    private func collectEdited() -> InvoiceFields {
        let categoryName = category.nilIfBlank
        let matched = categoryName.flatMap { name in
            config.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        return InvoiceFields(
            vendorName: vendor.nilIfBlank,
            gstin: gstin.nilIfBlank?.uppercased(),
            invoiceNumber: invoiceNumber.nilIfBlank,
            invoiceDate: hasDate ? invoiceDate : nil,
            taxableValue: Formatters.parseAmount(taxable),
            cgst: Formatters.parseAmount(cgst),
            sgst: Formatters.parseAmount(sgst),
            igst: Formatters.parseAmount(igst),
            discount: Formatters.parseAmount(discount),
            netAmount: Formatters.parseAmount(net),
            expenseCategoryId: matched?.id,
            expenseCategoryName: categoryName,
            remarks: remarks.nilIfBlank,
            supplierPhone: ocr.supplierPhone,
            supplierEmail: ocr.supplierEmail
        )
    }

    private func submit() async {
        guard !isSubmitting, let employee = session.employee else { return }
        error = nil
        let edited = collectEdited()

        if config.config?.remarksRequired == true, edited.remarks == nil {
            error = "Remarks are required by your company."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        if config.config?.duplicateCheckEnabled ?? true, !duplicateOverride {
            if await container.invoiceStore.findLocalDuplicate(gstin: edited.gstin, invoiceNumber: edited.invoiceNumber, excluding: draft.id) != nil {
                duplicateMessage = "You already captured an invoice with this number on this device."
                showDuplicateDialog = true
                return
            }
            if let remote = try? await container.remote.checkDuplicate(edited), remote.isDuplicate {
                duplicateMessage = remote.message
                showDuplicateDialog = true
                return
            }
        }

        var latitude: Double?
        var longitude: Double?
        if config.config?.requiresGps == true {
            do {
                let location = try await container.location.currentLocation()
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
            } catch {
                self.error = APIError.from(error).message
                return
            }
        }

        do {
            let store = container.invoiceStore
            let originalFile = try await store.writeImage(draft.original, name: "\(draft.id)_original.jpg")
            let compressedFile = try await store.writeImage(draft.compressed, name: "\(draft.id)_compressed.jpg")
            let thumbnailFile = try await store.writeImage(draft.thumbnail, name: "\(draft.id)_thumb.jpg")

            let invoice = LocalInvoice(
                localId: draft.id,
                serverId: nil,
                companyId: employee.companyId,
                employeeId: employee.id,
                branchId: employee.branchId,
                deviceId: container.sessionStore.deviceId,
                createdAt: Date(),
                uploadedAt: nil,
                syncStatus: .pending,
                approvalStatus: .pending,
                ocrData: ocr,
                editedData: edited,
                ocrConfidence: draft.extraction.confidence,
                originalImageFile: originalFile,
                compressedImageFile: compressedFile,
                thumbnailFile: thumbnailFile,
                latitude: latitude,
                longitude: longitude,
                idempotencyKey: draft.id,
                duplicateOverride: duplicateOverride,
                isQueued: true
            )
            await store.save(invoice)
            await sync.refreshCounts()
            Task { await sync.syncNow() }

            toasts.success("Invoice saved and queued for upload")
            onSubmitted()
        } catch {
            self.error = "Submit failed: \(APIError.from(error).message)"
        }
    }
}

// MARK: - Supporting views

struct FormSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content
    @Environment(\.brandColor) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(brand)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct ConfidenceRing: View {
    let value: Double
    let isLow: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(isLow ? Brand.warning : Brand.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Confidence").font(.caption).foregroundStyle(.secondary)
                Text(isLow ? "Needs review" : "Looks good")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isLow ? Brand.warning : Brand.success)
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
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
