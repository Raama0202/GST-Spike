import SwiftUI
import UniformTypeIdentifiers

struct ITCView: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL

    @State private var month = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var returnType: GSTReturnType = .gstr2b
    @State private var statusFilter: ITCMatchStatus?
    @State private var summary = ITCSummary()
    @State private var matches: [ITCMatch] = []
    @State private var imports: [ITCImport] = []
    @State private var followUps: [ITCFollowUp] = []
    @State private var isLoading = false
    @State private var busyAction: String?
    @State private var error: String?
    @State private var showImporter = false
    @State private var shareItem: ShareFile?
    @State private var reminderLinks: [ITCReminderLink] = []
    @State private var showReminderLinks = false

    private var period: String { Formatters.periodKey(month) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    periodCard
                    if let error {
                        ErrorBanner(message: error) { Task { await loadAll() } }
                    }
                    summaryGrid
                    actionsCard
                    matchesSection
                    if !followUps.isEmpty { followUpSection }
                    if !imports.isEmpty { importsSection }
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .refreshable { await loadAll() }
            .glassScreen()
            .navigationTitle("ITC Reconciliation")
        }
        .task(id: "\(period)-\(returnType.rawValue)") { await loadAll() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.importTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReminderLinks) {
            ReminderLinksSheet(links: reminderLinks)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var periodCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 40)
                }
                .buttonStyle(.glassSecondaryCompact)
                Spacer()
                VStack(spacing: 2) {
                    Text("Tax period").font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.month.string(from: month))
                        .font(.display(20, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 40)
                }
                .buttonStyle(.glassSecondaryCompact)
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
            }
            Picker("Return", selection: $returnType) {
                ForEach(GSTReturnType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .glassCard()
    }

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Match summary", subtitle: summary.total == 0 ? "Import \(returnType.title) to reconcile" : "\(summary.total) rows compared")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ITCMatchStatus.allCases) { status in
                    Button {
                        withAnimation(.snappy) { statusFilter = statusFilter == status ? nil : status }
                        Task { await loadMatches() }
                    } label: {
                        HStack(spacing: 10) {
                            IconBadge(systemImage: status.systemImage, color: status.color, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(summary.count(status))")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .contentTransition(.numericText())
                                Text(status.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .glassCard(padding: 12, tint: statusFilter == status ? status.color : nil)
                    }
                    .buttonStyle(AdminPressableStyle())
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actions")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                actionButton("Import \(returnType.title)", systemImage: "square.and.arrow.down.fill", id: "import", color: Brand.primary) {
                    showImporter = true
                }
                actionButton("Reconcile", systemImage: "arrow.triangle.2.circlepath", id: "reconcile", color: Brand.teal) {
                    Task { await reconcile() }
                }
                actionButton("Remind missing", systemImage: "bell.badge.fill", id: "remind", color: Brand.orange) {
                    Task { await remindMissing() }
                }
                actionButton("Export CSV", systemImage: "square.and.arrow.up.fill", id: "export", color: Brand.violet) {
                    Task { await export() }
                }
            }
            Text("Upload the GSTR-2A/2B Excel or CSV downloaded from the GST portal. Matching runs on the server exactly like the web dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func actionButton(_ title: String, systemImage: String, id: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busyAction == id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(AdminPressableStyle())
        .disabled(busyAction != nil)
    }

    // MARK: - Lists

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: statusFilter?.title ?? "All matches",
                subtitle: "\(matches.count) rows",
                trailing: statusFilter == nil ? nil : AnyView(
                    Button("Clear") {
                        statusFilter = nil
                        Task { await loadMatches() }
                    }
                    .font(.subheadline.weight(.semibold))
                )
            )
            if isLoading && matches.isEmpty {
                ForEach(0..<3, id: \.self) { _ in ShimmerRow() }
            } else if matches.isEmpty {
                EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No rows", message: "Import a return or pick another period.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(matches) { match in
                        ITCMatchRow(match: match, isBusy: busyAction == match.id) {
                            Task { await remind(match) }
                        }
                    }
                }
            }
        }
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Manual follow-ups", subtitle: "Suppliers without phone or email")
            ForEach(followUps) { item in
                FollowUpRow(item: item) { called, promised, resolved in
                    Task { await updateFollowUp(item, called: called, promised: promised, resolved: resolved) }
                }
            }
        }
    }

    private var importsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Import history")
            ForEach(imports.prefix(5)) { item in
                HStack(spacing: 12) {
                    IconBadge(systemImage: item.status == "failed" ? "xmark.octagon.fill" : "tablecells.fill", color: item.status == "failed" ? Brand.danger : Brand.teal, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.originalFilename ?? "GSTR-\(item.returnType)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(item.errorMessage ?? "\(item.rowCount) rows · GSTR-\(item.returnType) · \(Formatters.relativeString(item.createdAt))")
                            .font(.caption)
                            .foregroundStyle(item.errorMessage == nil ? Color.secondary : Brand.danger)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .glassCard(padding: 12)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Data

    private func shiftMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy) { month = next }
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await session.api.itcSummary(period: period, type: returnType)
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
        await loadMatches()
        imports = (try? await session.api.itcImports(period: period)) ?? []
        followUps = (try? await session.api.itcFollowUps()) ?? []
    }

    private func loadMatches() async {
        do {
            matches = try await session.api.itcMatches(period: period, type: returnType, status: statusFilter)
        } catch {
            if Task.isCancelled { return }
            matches = []
            self.error = APIError.from(error).message
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        busyAction = "import"
        defer { busyAction = nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = try await session.api.itcImport(period: period, type: returnType, fileName: url.lastPathComponent, data: data)
            if result.isProcessing {
                toasts.show("\(result.rowCount ?? 0) rows are being processed. Pull to refresh in a minute to see matches.")
            } else {
                summary = result
                toasts.success("Imported \(url.lastPathComponent) and reconciled")
            }
            await loadAll()
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func reconcile() async {
        busyAction = "reconcile"
        defer { busyAction = nil }
        do {
            summary = try await session.api.itcReconcile(period: period, type: returnType)
            toasts.success("Reconciliation refreshed")
            await loadMatches()
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func remindMissing() async {
        busyAction = "remind"
        defer { busyAction = nil }
        do {
            let batch = try await session.api.itcRemindMissing(period: period, type: returnType)
            if batch.count == 0 {
                toasts.show("No missing or mismatched invoices to remind")
            } else {
                reminderLinks = batch.items
                showReminderLinks = true
                followUps = (try? await session.api.itcFollowUps()) ?? followUps
            }
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func remind(_ match: ITCMatch) async {
        busyAction = match.id
        defer { busyAction = nil }
        do {
            let link = try await session.api.itcRemind(matchId: match.id)
            if let raw = link.whatsappUrl ?? link.mailtoUrl, let url = URL(string: raw) {
                openURL(url)
            } else {
                toasts.show("No supplier contact — added to manual follow-ups")
                followUps = (try? await session.api.itcFollowUps()) ?? followUps
            }
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func export() async {
        busyAction = "export"
        defer { busyAction = nil }
        do {
            let file = try await session.api.itcExport(period: period, type: returnType, status: statusFilter)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try file.csv.data(using: .utf8)?.write(to: url, options: .atomic)
            shareItem = ShareFile(url: url)
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func updateFollowUp(_ item: ITCFollowUp, called: Bool?, promised: Date?, resolved: Bool?) async {
        do {
            try await session.api.itcUpdateFollowUp(item.id, called: called, promisedBy: promised, resolved: resolved)
            if resolved == true { toasts.success("Marked as resolved") }
            followUps = (try? await session.api.itcFollowUps()) ?? followUps
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private static var importTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .spreadsheet, .json]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        if let xls = UTType(filenameExtension: "xls") { types.append(xls) }
        return types
    }
}

// MARK: - Rows

private struct ITCMatchRow: View {
    let match: ITCMatch
    let isBusy: Bool
    let onRemind: () -> Void

    var body: some View {
        let status = match.matchStatus
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(match.invoice?.gstin ?? match.portalRow?.supplierGstin ?? "No GSTIN")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(status?.title ?? match.status, systemImage: status?.systemImage ?? "circle")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(status?.color ?? .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((status?.color ?? .gray).opacity(0.15), in: Capsule())
            }
            HStack(spacing: 12) {
                column("Books", number: match.invoice?.invoiceNumber, amount: match.invoice?.netAmount)
                Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(.tertiary)
                column("Portal", number: match.portalRow?.invoiceNumber, amount: match.portalRow?.netAmount)
            }
            if let delta = match.amountDelta, abs(delta) > 0.009 {
                Text("Difference \(Formatters.currency(delta))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.danger)
            }
            if let notes = match.notes?.nilIfBlank {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            if match.canRemind {
                Button(action: onRemind) {
                    HStack {
                        if isBusy { ProgressView().controlSize(.small) } else { Image(systemName: "paperplane.fill") }
                        Text(match.invoice?.supplierPhone != nil ? "Remind on WhatsApp" : (match.invoice?.supplierEmail != nil ? "Remind by email" : "Log follow-up"))
                    }
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glassSecondary(tint: Brand.orange, fullWidth: true))
                .disabled(isBusy)
            }
        }
        .glassCard(padding: 14)
    }

    private func column(_ title: String, number: String?, amount: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.tertiary).textCase(.uppercase)
            Text(number ?? "—").font(.caption).lineLimit(1)
            Text(amount.map { Formatters.currency($0) } ?? "—").font(.footnote.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FollowUpRow: View {
    let item: ITCFollowUp
    let onUpdate: (Bool?, Date?, Bool?) -> Void
    @State private var promised = Date().addingTimeInterval(3 * 86_400)
    @State private var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.messagePreview ?? "Supplier reminder")
                .font(.footnote)
                .lineLimit(3)
            HStack(spacing: 8) {
                GlassChip(title: item.called ? "Called" : "Mark called", systemImage: "phone.fill", isSelected: item.called) {
                    onUpdate(!item.called, nil, nil)
                }
                GlassChip(title: item.promisedBy.map { "By \(Formatters.dayString($0))" } ?? "Promise date", systemImage: "calendar", isSelected: item.promisedBy != nil) {
                    showDate.toggle()
                }
                Spacer()
                Button {
                    onUpdate(nil, nil, true)
                } label: {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.success)
                }
                .accessibilityLabel("Resolve")
            }
            if showDate {
                HStack {
                    DatePicker("Promised by", selection: $promised, in: Date()..., displayedComponents: .date)
                        .font(.footnote)
                    Button("Save") {
                        onUpdate(nil, promised, nil)
                        showDate = false
                    }
                    .font(.footnote.weight(.bold))
                }
            }
        }
        .glassCard(padding: 14)
        .animation(.snappy, value: showDate)
    }
}

private struct ReminderLinksSheet: View {
    let links: [ITCReminderLink]
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    InfoBanner(message: "WhatsApp and email reminders open on your device — tap each to send. Suppliers without contacts were added to manual follow-ups.", systemImage: "info.circle.fill", color: Brand.primary)
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        HStack(spacing: 12) {
                            IconBadge(systemImage: link.whatsappUrl != nil ? "message.fill" : (link.mailtoUrl != nil ? "envelope.fill" : "phone.badge.waveform.fill"), color: link.whatsappUrl != nil ? Brand.success : Brand.primary, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.contactPhone ?? link.contactEmail ?? "Manual follow-up")
                                    .font(.subheadline.weight(.semibold))
                                Text(link.message ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if let raw = link.whatsappUrl ?? link.mailtoUrl, let url = URL(string: raw) {
                                Button("Send") { openURL(url) }
                                    .buttonStyle(.glassPrimaryCompact)
                            }
                        }
                        .glassCard(padding: 12)
                    }
                }
                .padding(GlassMetrics.screenPadding)
            }
            .glassScreen()
            .navigationTitle("\(links.count) reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Sharing

struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
