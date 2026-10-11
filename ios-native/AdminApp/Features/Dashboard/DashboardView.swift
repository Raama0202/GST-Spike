import SwiftUI
import Charts

struct DashboardView: View {
    @Binding var selection: CompanyAdminTab
    @Binding var invoiceFilter: String?

    @Environment(AdminSession.self) private var session
    @Environment(AdminWorkspace.self) private var workspace
    @State private var recent: [AdminInvoice] = []
    @State private var loadingRecent = true

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
    }

    private var slices: [Slice] {
        let s = workspace.stats
        return [
            Slice(id: "pending", label: "Pending", value: s.pendingCount, color: Brand.warning),
            Slice(id: "approved", label: "Approved", value: s.approvedCount, color: Brand.success),
            Slice(id: "returned", label: "Returned", value: s.returnedCount, color: Brand.orange),
            Slice(id: "rejected", label: "Rejected", value: s.rejectedCount, color: Brand.danger),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let error = workspace.statsError {
                        ErrorBanner(message: error) { Task { await reload() } }
                    }
                    pendingHero
                    statGrid
                    chartCard
                    recentSection
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .refreshable { await reload() }
            .glassScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AdminInvoice.self) { invoice in
                InvoiceReviewView(invoiceId: invoice.id)
            }
        }
        .task { await loadRecent() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(workspace.companyName ?? "Overview")
                    .font(.display(28, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            AvatarView(name: session.user?.email ?? "A", size: 46)
        }
        .padding(.top, 12)
    }

    private var pendingHero: some View {
        Button {
            invoiceFilter = "pending"
            selection = .invoices
        } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Awaiting your review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(workspace.stats.pendingCount)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Label("Review now", systemImage: "arrow.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                Spacer()
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.bounce, value: workspace.stats.pendingCount)
            }
            .padding(22)
            .background(
                LinearGradient(colors: [Brand.indigo, Brand.violet, Brand.pink.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Brand.violet.opacity(0.35), radius: 24, y: 12)
        }
        .buttonStyle(AdminPressableStyle())
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            StatTile(title: "Today", value: "\(workspace.stats.todayUploads)", systemImage: "calendar.badge.clock", color: Brand.cyan, caption: "uploads")
            statButton(title: "Approved", value: workspace.stats.approvedCount, systemImage: "checkmark.seal.fill", color: Brand.success, filter: "approved")
            statButton(title: "Returned", value: workspace.stats.returnedCount, systemImage: "arrow.uturn.backward.circle.fill", color: Brand.orange, filter: "returned")
            statButton(title: "Rejected", value: workspace.stats.rejectedCount, systemImage: "xmark.seal.fill", color: Brand.danger, filter: "rejected")
        }
    }

    private func statButton(title: String, value: Int, systemImage: String, color: Color, filter: String) -> some View {
        Button {
            invoiceFilter = filter
            selection = .invoices
        } label: {
            StatTile(title: title, value: "\(value)", systemImage: systemImage, color: color)
        }
        .buttonStyle(AdminPressableStyle())
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Approval mix", subtitle: "\(workspace.stats.total) invoices all time")
            if workspace.stats.total == 0 {
                Text("No invoices yet. Employees' uploads from Android and iOS will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Count", slice.value),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(5)
                        .foregroundStyle(slice.color.gradient)
                    }
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text("\(approvalRate)%")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                            Text("approved")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 10, height: 10)
                                Text(slice.label).font(.footnote)
                                Spacer()
                                Text("\(slice.value)").font(.footnote.weight(.bold)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Latest submissions",
                trailing: AnyView(
                    Button("See all") {
                        invoiceFilter = nil
                        selection = .invoices
                    }
                    .font(.subheadline.weight(.semibold))
                )
            )
            if loadingRecent && recent.isEmpty {
                ForEach(0..<3, id: \.self) { _ in ShimmerRow() }
            } else if recent.isEmpty {
                EmptyStateView(systemImage: "tray", title: "Nothing yet", message: "New uploads appear here in real time.")
            } else {
                ForEach(recent) { invoice in
                    NavigationLink(value: invoice) {
                        AdminInvoiceRow(invoice: invoice)
                    }
                    .buttonStyle(AdminPressableStyle())
                }
            }
        }
    }

    private var approvalRate: Int {
        let total = workspace.stats.total
        guard total > 0 else { return 0 }
        return Int((Double(workspace.stats.approvedCount) / Double(total) * 100).rounded())
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func reload() async {
        await workspace.refreshStats()
        await loadRecent()
    }

    private func loadRecent() async {
        loadingRecent = true
        defer { loadingRecent = false }
        if let page = try? await session.api.invoices(status: nil) {
            recent = Array(page.items.prefix(5))
        }
    }
}

struct AdminPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
