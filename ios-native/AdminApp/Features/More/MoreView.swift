import SwiftUI

enum MoreRoute: Hashable {
    case catalog(CatalogKind)
    case announcements
    case settings
    case profile
}

struct MoreView: View {
    @Environment(AdminSession.self) private var session
    @Environment(AdminWorkspace.self) private var workspace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        AvatarView(name: session.user?.email ?? "A", size: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workspace.companyName ?? "Company")
                                .font(.headline)
                            Text(session.user?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(status: "active", compact: true)
                    }
                    .glassCard()

                    VStack(spacing: 0) {
                        link(.catalog(.categories), title: "Expense categories", subtitle: "Shown on the employee review form", systemImage: "square.grid.2x2.fill", color: Brand.violet)
                        GlassDivider().padding(.vertical, 4)
                        link(.catalog(.branches), title: "Branches", subtitle: "Assign employees to locations", systemImage: "building.2.fill", color: Brand.teal)
                        GlassDivider().padding(.vertical, 4)
                        link(.announcements, title: "Announcements", subtitle: "Notify every employee", systemImage: "megaphone.fill", color: Brand.orange)
                    }
                    .glassCard()

                    VStack(spacing: 0) {
                        link(.settings, title: "Company settings", subtitle: "Branding, GPS, duplicates, OCR", systemImage: "slider.horizontal.3", color: Brand.primary)
                        GlassDivider().padding(.vertical, 4)
                        link(.profile, title: "Account", subtitle: "Server, version, sign out", systemImage: "person.crop.circle.fill", color: Brand.pink)
                    }
                    .glassCard()
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .glassScreen()
            .navigationTitle("More")
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .catalog(let kind): CatalogView(kind: kind)
                case .announcements: AnnouncementsView()
                case .settings: CompanySettingsView()
                case .profile: AdminProfileView()
                }
            }
        }
    }

    private func link(_ route: MoreRoute, title: String, subtitle: String, systemImage: String, color: Color) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                IconBadge(systemImage: systemImage, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Categories & branches

struct CatalogView: View {
    let kind: CatalogKind

    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var items: [CatalogItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var editing: CatalogEditorTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    ErrorBanner(message: error) { Task { await load() } }
                }
                if isLoading && items.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in ShimmerRow() }
                } else if items.isEmpty {
                    EmptyStateView(systemImage: kind.systemImage, title: "No \(kind.title.lowercased())", message: "Add your first \(kind.singular.lowercased()).", actionTitle: "Add \(kind.singular.lowercased())") {
                        editing = .new
                    }
                } else {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .refreshable { await load() }
        .glassScreen()
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = .new } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { target in
            CatalogEditor(kind: kind, target: target, parents: kind == .categories ? items.filter { $0.parentId == nil && $0.isActive } : []) { _ in
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func row(_ item: CatalogItem) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: kind.systemImage, color: item.isActive ? (kind == .categories ? Brand.violet : Brand.teal) : .gray, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold))
                if let code = item.code?.nilIfBlank {
                    Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                } else if let parent = items.first(where: { $0.id == item.parentId }) {
                    Text("Under \(parent.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !item.isActive { StatusPill(status: "inactive", compact: true) }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .glassCard(padding: 14)
        .opacity(item.isActive ? 1 : 0.65)
        .contentShape(Rectangle())
        .onTapGesture { editing = .edit(item) }
        .contextMenu {
            if item.isActive {
                Button(role: .destructive) { Task { await deactivate(item) } } label: {
                    Label("Deactivate", systemImage: "archivebox")
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await session.api.catalog(kind).sorted {
                $0.isActive != $1.isActive ? $0.isActive : ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name)
            }
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
    }

    private func deactivate(_ item: CatalogItem) async {
        do {
            try await session.api.deactivateCatalog(kind, id: item.id)
            toasts.success("\(item.name) deactivated")
            await load()
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }
}

enum CatalogEditorTarget: Identifiable {
    case new
    case edit(CatalogItem)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let item): return item.id
        }
    }
}

private struct CatalogEditor: View {
    let kind: CatalogKind
    let target: CatalogEditorTarget
    let parents: [CatalogItem]
    let onSaved: (CatalogItem) -> Void

    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var parentId: String?
    @State private var sortOrder = 0
    @State private var isActive = true
    @State private var isSaving = false
    @State private var error: String?

    private var existing: CatalogItem? {
        if case .edit(let item) = target { return item }
        return nil
    }

    private var isValid: Bool {
        name.nilIfBlank != nil && (kind == .categories || code.nilIfBlank != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        GlassTextField(title: "Name", text: $name, systemImage: kind.systemImage, prompt: kind == .categories ? "Travel" : "Head Office", capitalization: .words)
                        if kind == .branches {
                            GlassTextField(title: "Code (required)", text: $code, systemImage: "number", prompt: "HO", capitalization: .characters)
                        } else {
                            if !parents.filter({ $0.id != existing?.id }).isEmpty {
                                Picker("Parent", selection: $parentId) {
                                    Text("None (top level)").tag(String?.none)
                                    ForEach(parents.filter { $0.id != existing?.id }) { parent in
                                        Text(parent.name).tag(Optional(parent.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Stepper("Sort order: \(sortOrder)", value: $sortOrder, in: 0...999)
                                .font(.subheadline)
                        }
                        GlassToggleRow(title: "Active", subtitle: "Inactive items are hidden from employees", systemImage: "eye.fill", isOn: $isActive)
                    }
                    .glassCard()
                    if let error { ErrorBanner(message: error) }
                    Button {
                        Task { await save() }
                    } label: {
                        LoadingLabel(title: existing == nil ? "Add \(kind.singular.lowercased())" : "Save", systemImage: "checkmark.circle.fill", isLoading: isSaving)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(!isValid || isSaving)
                }
                .padding(GlassMetrics.screenPadding)
            }
            .glassScreen()
            .navigationTitle(existing == nil ? "New \(kind.singular.lowercased())" : "Edit \(kind.singular.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            code = existing.code ?? ""
            parentId = existing.parentId
            sortOrder = existing.sortOrder
            isActive = existing.isActive
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        let input = CatalogInput(
            name: name.trimmingCharacters(in: .whitespaces),
            code: kind == .branches ? code.nilIfBlank : nil,
            parentId: kind == .categories ? parentId : nil,
            sortOrder: sortOrder,
            isActive: isActive
        )
        do {
            let saved: CatalogItem
            if let existing {
                saved = try await session.api.updateCatalog(kind, id: existing.id, input)
            } else {
                saved = try await session.api.createCatalog(kind, input)
            }
            onSaved(saved)
            toasts.success("\(saved.name) saved — employees get it on next sync")
            dismiss()
        } catch {
            self.error = APIError.from(error).message
        }
    }
}

// MARK: - Announcements

struct AnnouncementsView: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var title = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var history: [AnnouncementGroup] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 14) {
                    GlassTextField(title: "Title", text: $title, systemImage: "textformat", prompt: "Month-end submission deadline")
                    GlassTextField(title: "Message", text: $message, systemImage: "text.alignleft", prompt: "Please upload all bills by the 28th.", axis: .vertical)
                    Button {
                        Task { await send() }
                    } label: {
                        LoadingLabel(title: "Send to all employees", systemImage: "paperplane.fill", isLoading: isSending)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(title.nilIfBlank == nil || message.nilIfBlank == nil || isSending)
                    Text("Delivered to Android and iOS employee apps on their next sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .glassCard()

                SectionHeader(title: "Sent", subtitle: history.isEmpty ? nil : "\(history.count) announcements")
                if isLoading && history.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in ShimmerRow() }
                } else if history.isEmpty {
                    EmptyStateView(systemImage: "megaphone", title: "No announcements", message: "Messages you send appear here with read counts.")
                } else {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(Formatters.relativeString(item.createdAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(item.body).font(.footnote).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "eye.fill")
                                Text("\(item.readCount)/\(item.recipients) read")
                                ProgressView(value: Double(item.readCount), total: Double(max(item.recipients, 1)))
                                    .tint(Brand.success)
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        .glassCard(padding: 14)
                    }
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .refreshable { await load() }
        .glassScreen()
        .navigationTitle("Announcements")
        .task { await load() }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let count = try await session.api.announce(title: title.trimmingCharacters(in: .whitespaces), body: message.trimmingCharacters(in: .whitespacesAndNewlines))
            toasts.success("Sent to \(count) employee\(count == 1 ? "" : "s")")
            title = ""
            message = ""
            await load()
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await session.api.announcementHistory()
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        } catch {
            if !Task.isCancelled { toasts.error(APIError.from(error).message) }
        }
    }
}
