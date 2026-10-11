import SwiftUI

struct UploadsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case queued = "Pending sync"
        case review = "In review"
        case approved = "Approved"
        case attention = "Needs attention"
        var id: String { rawValue }

        func matches(_ invoice: LocalInvoice) -> Bool {
            switch self {
            case .all: return true
            case .queued: return invoice.syncStatus != .uploaded
            case .review: return invoice.syncStatus == .uploaded && (invoice.approvalStatus == .uploaded || invoice.approvalStatus == .pending)
            case .approved: return invoice.approvalStatus == .approved
            case .attention: return invoice.approvalStatus == .rejected || invoice.approvalStatus == .returned || invoice.syncStatus == .failed
            }
        }
    }

    @Environment(EmployeeContainer.self) private var container
    @Environment(SyncEngine.self) private var sync
    @State private var invoices: [LocalInvoice] = []
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var loaded = false

    private var visible: [LocalInvoice] {
        invoices.filter { invoice in
            guard filter.matches(invoice) else { return false }
            guard let query = search.nilIfBlank?.lowercased() else { return true }
            let d = invoice.display
            return [d.vendorName, d.invoiceNumber, d.gstin, d.expenseCategoryName]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private var totalVisible: Double {
        visible.compactMap(\.display.netAmount).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    filters
                    if !loaded {
                        ForEach(0..<4, id: \.self) { _ in ShimmerRow() }
                    } else if visible.isEmpty {
                        EmptyStateView(
                            systemImage: filter == .all ? "tray" : "line.3.horizontal.decrease.circle",
                            title: filter == .all ? "No uploads yet" : "Nothing here",
                            message: filter == .all ? "Scan an invoice to get started." : "No invoices match this filter."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visible) { invoice in
                                NavigationLink(value: invoice.localId) {
                                    InvoiceRow(invoice: invoice)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .searchable(text: $search, prompt: "Vendor, invoice # or GSTIN")
            .refreshable { await sync.syncNow() }
            .glassScreen()
            .navigationTitle("My Uploads")
            .navigationDestination(for: String.self) { localId in
                UploadDetailView(localId: localId)
            }
        }
        .task(id: sync.revision) {
            invoices = await container.invoiceStore.all()
            loaded = true
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(visible.count) invoice\(visible.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Formatters.currency(totalVisible))
                    .font(.display(28, weight: .heavy))
                    .contentTransition(.numericText())
            }
            Spacer()
            IconBadge(systemImage: "indianrupeesign", color: Brand.success, size: 46)
        }
        .glassCard()
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    GlassChip(title: item.rawValue, isSelected: filter == item) { filter = item }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
