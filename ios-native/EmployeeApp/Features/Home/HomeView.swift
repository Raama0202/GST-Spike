import SwiftUI

struct HomeView: View {
    @Binding var selection: EmployeeTab
    @Binding var showScanner: Bool

    @Environment(EmployeeContainer.self) private var container
    @Environment(SessionModel.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(NotificationsModel.self) private var notifications
    @Environment(CompanyConfigModel.self) private var config
    @Environment(\.brandColor) private var brand

    @State private var recent: [LocalInvoice] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    scanHero
                    stats
                    syncCard
                    recentSection
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .refreshable { await sync.syncNow() }
            .glassScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { localId in
                UploadDetailView(localId: localId)
            }
        }
        .task(id: sync.revision) {
            recent = Array(await container.invoiceStore.all().prefix(4))
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(name: session.employee?.name ?? "?", size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(session.employee?.firstName ?? "")
                    .font(.display(26, weight: .heavy))
                    .lineLimit(1)
            }
            Spacer()
            GlassIconButton(systemImage: "bell.fill", badge: notifications.unreadCount) {
                selection = .alerts
            }
        }
        .padding(.top, 6)
    }

    private var scanHero: some View {
        Button {
            showScanner = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [brand, Brand.violet, Brand.pink.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))

                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 120, weight: .thin))
                    .foregroundStyle(.white.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 14)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text(config.config?.companyName ?? session.employee?.companyName ?? "Your company")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                    Text("Scan an invoice")
                        .font(.display(28, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Auto-crop, extract GST fields and submit — even offline.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                        Text("Start scanning")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(brand)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .padding(.top, 4)
                }
                .padding(22)
            }
            .frame(height: 230)
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            .shadow(color: brand.opacity(0.45), radius: 26, x: 0, y: 16)
        }
        .buttonStyle(PressableStyle())
    }

    private var stats: some View {
        HStack(spacing: 14) {
            StatTile(title: "Today's uploads", value: "\(sync.todayCount)", systemImage: "arrow.up.doc.fill", color: brand)
            StatTile(
                title: "Pending sync",
                value: "\(sync.pendingCount)",
                systemImage: sync.pendingCount > 0 ? "icloud.and.arrow.up.fill" : "checkmark.icloud.fill",
                color: sync.pendingCount > 0 ? Brand.warning : Brand.success,
                caption: sync.isOnline ? nil : "Offline"
            )
        }
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(systemImage: sync.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash", color: sync.isOnline ? Brand.cyan : Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncTitle).font(.headline)
                    Text(syncSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if sync.isSyncing {
                ProgressView().progressViewStyle(.linear).tint(brand)
            }
            if let error = sync.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Brand.danger)
            }
            Button {
                Task { await sync.syncNow() }
            } label: {
                LoadingLabel(title: sync.isSyncing ? "Syncing…" : "Sync now", systemImage: "icloud.and.arrow.up", isLoading: sync.isSyncing)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.glassSecondary)
            .disabled(sync.isSyncing)
        }
        .glassCard()
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Recent uploads",
                trailing: AnyView(
                    Button("See all") { selection = .uploads }
                        .font(.subheadline.weight(.semibold))
                )
            )
            if recent.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "No invoices yet",
                    message: "Your scanned invoices will appear here.",
                    actionTitle: "Scan first invoice",
                    action: { showScanner = true }
                )
            } else {
                ForEach(recent) { invoice in
                    NavigationLink(value: invoice.localId) {
                        InvoiceRow(invoice: invoice)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: - Text

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var syncTitle: String {
        if !sync.isOnline { return "You're offline" }
        if sync.isSyncing { return "Uploading invoices" }
        return sync.pendingCount > 0 ? "\(sync.pendingCount) waiting to upload" : "Everything is synced"
    }

    private var syncSubtitle: String {
        if !sync.isOnline { return "Invoices are saved and will upload automatically." }
        if let last = sync.lastSyncedAt { return "Last synced \(Formatters.relativeString(last))" }
        return "Uploads retry automatically in the background."
    }
}

/// Subtle press-down feedback for card-style buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
