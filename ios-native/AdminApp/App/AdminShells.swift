import SwiftUI
import Observation

/// Company-wide counters shared by the dashboard and the invoice tab badge.
@MainActor
@Observable
final class AdminWorkspace {
    private(set) var stats = DashboardStats()
    private(set) var statsError: String? = nil
    private(set) var isLoadingStats = false
    private(set) var companyName: String? = nil
    @ObservationIgnored private let api: AdminAPI

    init(api: AdminAPI) {
        self.api = api
    }

    func refreshStats() async {
        isLoadingStats = true
        defer { isLoadingStats = false }
        do {
            stats = try await api.dashboard()
            statsError = nil
        } catch {
            statsError = APIError.from(error).message
        }
    }

    func loadCompanyName() async {
        guard companyName == nil else { return }
        companyName = (try? await api.settings())?.name.nilIfBlank
    }

    func setCompanyName(_ name: String) { companyName = name }
}

enum CompanyAdminTab: Hashable {
    case dashboard, invoices, itc, team, more
}

struct CompanyAdminShell: View {
    @Environment(AdminSession.self) private var session
    @State private var workspace: AdminWorkspace?
    @State private var selection: CompanyAdminTab = .dashboard
    @State private var invoiceFilter: String? = "pending"

    var body: some View {
        Group {
            if let workspace {
                ZStack(alignment: .bottom) {
                    ZStack {
                        tab(.dashboard) { DashboardView(selection: $selection, invoiceFilter: $invoiceFilter) }
                        tab(.invoices) { AdminInvoicesView(filter: $invoiceFilter) }
                        tab(.itc) { ITCView() }
                        tab(.team) { EmployeesView() }
                        tab(.more) { MoreView() }
                    }
                    FloatingTabBar(
                        items: [
                            TabItem(id: CompanyAdminTab.dashboard, title: "Overview", systemImage: "square.grid.2x2"),
                            TabItem(id: CompanyAdminTab.invoices, title: "Invoices", systemImage: "doc.text.magnifyingglass", badge: workspace.stats.pendingCount),
                            TabItem(id: CompanyAdminTab.itc, title: "ITC", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard"),
                            TabItem(id: CompanyAdminTab.team, title: "Team", systemImage: "person.2"),
                            TabItem(id: CompanyAdminTab.more, title: "More", systemImage: "ellipsis.circle"),
                        ],
                        selection: $selection
                    )
                }
                .ignoresSafeArea(.keyboard)
                .environment(workspace)
                .task {
                    await workspace.refreshStats()
                    await workspace.loadCompanyName()
                }
            } else {
                Color.clear.background(GlassBackground())
            }
        }
        .onAppear {
            if workspace == nil { workspace = AdminWorkspace(api: session.api) }
        }
    }

    @ViewBuilder
    private func tab<Content: View>(_ id: CompanyAdminTab, @ViewBuilder content: () -> Content) -> some View {
        let active = selection == id
        content()
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: GlassMetrics.tabBarClearance) }
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}