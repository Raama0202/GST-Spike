import SwiftUI

struct AdminInvoicesView: View {
    @Binding var filter: String?

    @Environment(AdminSession.self) private var session
    @Environment(AdminWorkspace.self) private var workspace
    @State private var invoices: [AdminInvoice] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""

    private let filters: [(id: String?, title: String)] = [
        ("pending", "Pending"), ("approved", "Approved"), ("returned", "Returned"), ("rejected", "Rejected"), (nil, "All"),
    ]

    private var visible: [AdminInvoice] {
        guard let query = search.nilIfBlank?.lowercased() else { return invoices }
        return invoices.filter { invoice in
            [invoice.vendor, invoice.number, invoice.gst, invoice.category]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filterBar
                    if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    }
                    if isLoading && invoices.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in ShimmerRow() }
                    } else if visible.isEmpty {
                        EmptyStateView(
                            systemImage: filter == "pending" ? "checkmark.circle" : "tray",
                            title: filter == "pending" ? "Inbox zero" : "No invoices",
                            message: filter == "pending" ? "Every submitted invoice has been reviewed." : "Nothing matches this filter yet."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visible) { invoice in
                                NavigationLink(value: invoice) {
                                    AdminInvoiceRow(invoice: invoice)
                                }
                                .buttonStyle(AdminPressableStyle())
                            }
                            if hasMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .task(id: page) { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .searchable(text: $search, prompt: "Vendor, invoice # or GSTIN")
            .refreshable { await load() }
            .glassScreen()
            .navigationTitle("Invoices")
            .navigationDestination(for: AdminInvoice.self) { invoice in
                InvoiceReviewView(invoiceId: invoice.id) { updated in
                    if let index = invoices.firstIndex(where: { $0.id == updated.id }) {
                        if filter == nil || filter == updated.approvalStatus {
                            invoices[index] = updated
                        } else {
                            invoices.remove(at: index)
                        }
                    }
                }
            }
        }
        .task(id: "\(filter ?? "all")|\(serverSearch ?? "")") {
            if serverSearch != nil {
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
            }
            await load()
        }
    }

    private var serverSearch: String? {
        search.trimmingCharacters(in: .whitespaces).nilIfBlank.map { String($0.prefix(100)) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.title) { item in
                    GlassChip(title: item.title, isSelected: filter == item.id) {
                        withAnimation(.snappy) { filter = item.id }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let first = try await session.api.invoices(status: filter, search: serverSearch, page: 1)
            invoices = first.items
            page = 1
            hasMore = first.hasMore
            error = nil
        } catch {
            if Task.isCancelled { return }
            self.error = APIError.from(error).message
        }
        await workspace.refreshStats()
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let requestedFilter = filter
        let requestedSearch = serverSearch
        do {
            let next = try await session.api.invoices(status: requestedFilter, search: requestedSearch, page: page + 1)
            guard requestedFilter == filter, requestedSearch == serverSearch else { return }
            let known = Set(invoices.map(\.id))
            invoices.append(contentsOf: next.items.filter { !known.contains($0.id) })
            page += 1
            hasMore = next.hasMore && !next.items.isEmpty
        } catch {
            hasMore = false
            self.error = APIError.from(error).message
        }
    }
}

struct AdminInvoiceRow: View {
    let invoice: AdminInvoice

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(path: invoice.thumbnailUrl ?? invoice.imageUrl)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(invoice.vendor)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let number = invoice.number {
                        Text("#\(number)").lineLimit(1)
                    }
                    if let date = invoice.uploadedAt {
                        Text("·")
                        Text(Formatters.relativeString(date))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                StatusPill(status: invoice.approvalStatus, compact: true)
            }
            Spacer(minLength: 8)
            Text(Formatters.currency(invoice.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .glassCard(padding: 14)
        .contentShape(Rectangle())
    }
}

/// Server images are signed `/v1/media/...` paths or absolute R2 URLs.
struct RemoteImage: View {
    let path: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url = ServerConfig.absoluteURL(path) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder(systemImage: "photo.badge.exclamationmark")
                default:
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
            }
        } else {
            placeholder(systemImage: "doc.text.image")
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
