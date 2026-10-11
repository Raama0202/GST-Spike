import SwiftUI

struct EmployeesView: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var employees: [AdminEmployee] = []
    @State private var branches: [CatalogItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""
    @State private var showInactive = false
    @State private var editing: EmployeeEditorTarget?
    @State private var confirmDeactivate: AdminEmployee?

    private var visible: [AdminEmployee] {
        employees.filter { employee in
            guard showInactive || employee.isActive else { return false }
            guard let query = search.nilIfBlank?.lowercased() else { return true }
            return [employee.name, employee.mobile, employee.employeeCode, employee.branchName ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    }
                    if isLoading && employees.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in ShimmerRow() }
                    } else if visible.isEmpty {
                        EmptyStateView(
                            systemImage: "person.2.slash",
                            title: employees.isEmpty ? "No employees yet" : "No matches",
                            message: employees.isEmpty ? "Add employees so they can sign in with OTP on Android or iOS." : "Try a different search.",
                            actionTitle: employees.isEmpty ? "Add employee" : nil,
                            action: employees.isEmpty ? { editing = .new } : nil
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visible) { employee in
                                employeeRow(employee)
                            }
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .searchable(text: $search, prompt: "Name, mobile or code")
            .refreshable { await load() }
            .glassScreen()
            .navigationTitle("Team")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = .new } label: {
                        Image(systemName: "person.badge.plus").font(.headline)
                    }
                    .accessibilityLabel("Add employee")
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { target in
            EmployeeEditor(target: target, branches: branches.filter(\.isActive)) { saved in
                if let index = employees.firstIndex(where: { $0.id == saved.id }) {
                    employees[index] = saved
                } else {
                    employees.append(saved)
                    employees.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
        }
        .confirmationDialog("Deactivate employee?", isPresented: Binding(get: { confirmDeactivate != nil }, set: { if !$0 { confirmDeactivate = nil } }), titleVisibility: .visible) {
            Button("Deactivate", role: .destructive) {
                if let employee = confirmDeactivate { Task { await deactivate(employee) } }
            }
        } message: {
            Text("\(confirmDeactivate?.name ?? "This employee") will no longer be able to sign in. Existing invoices are kept.")
        }
    }

    private var summary: some View {
        let active = employees.filter(\.isActive).count
        return HStack(spacing: 14) {
            StatTile(title: "Active", value: "\(active)", systemImage: "person.fill.checkmark", color: Brand.success)
            StatTile(title: "Inactive", value: "\(employees.count - active)", systemImage: "person.fill.xmark", color: .gray)
        }
        .overlay(alignment: .topTrailing) {
            Toggle("Show inactive", isOn: $showInactive.animation())
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .padding(10)
                .opacity(employees.count - active > 0 ? 1 : 0)
        }
    }

    private func employeeRow(_ employee: AdminEmployee) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: employee.name, size: 46)
                .saturation(employee.isActive ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(employee.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(employee.mobile) · \(employee.employeeCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let branch = employee.branchName {
                    Label(branch, systemImage: "mappin.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !employee.isActive {
                StatusPill(status: "inactive", compact: true)
            }
            Menu {
                Button { editing = .edit(employee) } label: { Label("Edit", systemImage: "pencil") }
                if employee.isActive {
                    Button(role: .destructive) { confirmDeactivate = employee } label: {
                        Label("Deactivate", systemImage: "person.fill.xmark")
                    }
                } else {
                    Button { Task { await reactivate(employee) } } label: {
                        Label("Reactivate", systemImage: "person.fill.checkmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .glassCard(padding: 14)
        .opacity(employee.isActive ? 1 : 0.7)
        .contentShape(Rectangle())
        .onTapGesture { editing = .edit(employee) }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            employees = try await session.api.employees()
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
        branches = (try? await session.api.catalog(.branches)) ?? branches
    }

    private func deactivate(_ employee: AdminEmployee) async {
        do {
            try await session.api.deactivateEmployee(employee.id)
            if let index = employees.firstIndex(where: { $0.id == employee.id }) {
                employees[index].isActive = false
            }
            toasts.success("\(employee.name) deactivated")
        } catch {
            toasts.error(APIError.from(error).message)
        }
        confirmDeactivate = nil
    }

    private func reactivate(_ employee: AdminEmployee) async {
        do {
            let input = EmployeeInput(name: employee.name, mobile: employee.mobile, employeeCode: employee.employeeCode, branchId: employee.branchId, isActive: true)
            let saved = try await session.api.updateEmployee(employee.id, input)
            if let index = employees.firstIndex(where: { $0.id == employee.id }) { employees[index] = saved }
            toasts.success("\(employee.name) reactivated")
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }
}

enum EmployeeEditorTarget: Identifiable {
    case new
    case edit(AdminEmployee)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let employee): return employee.id
        }
    }
}

private struct EmployeeEditor: View {
    let target: EmployeeEditorTarget
    let branches: [CatalogItem]
    let onSaved: (AdminEmployee) -> Void

    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mobile = ""
    @State private var code = ""
    @State private var branchId: String?
    @State private var isActive = true
    @State private var isSaving = false
    @State private var error: String?

    private var existing: AdminEmployee? {
        if case .edit(let employee) = target { return employee }
        return nil
    }

    private var mobileDigits: String { mobile.filter(\.isNumber) }
    private var isValid: Bool {
        name.nilIfBlank != nil && (10...15).contains(mobileDigits.count) && code.nilIfBlank != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AvatarView(name: name.nilIfBlank ?? "?", size: 72)
                        .padding(.top, 8)
                    VStack(spacing: 14) {
                        GlassTextField(title: "Full name", text: $name, systemImage: "person.fill", prompt: "Ravi Kumar", capitalization: .words)
                        GlassTextField(title: "Mobile", text: $mobile, systemImage: "phone.fill", prompt: "9876543210", keyboard: .phonePad)
                        GlassTextField(title: "Employee code", text: $code, systemImage: "number", prompt: "EMP001", capitalization: .characters)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Branch")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.leading, 4)
                            Menu {
                                Button("No branch") { branchId = nil }
                                ForEach(branches) { branch in
                                    Button(branch.name) { branchId = branch.id }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "building.2").foregroundStyle(.secondary)
                                    Text(branches.first { $0.id == branchId }?.name ?? "No branch")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                            }
                        }

                        GlassToggleRow(title: "Active", subtitle: "Inactive employees cannot sign in", systemImage: "checkmark.shield.fill", isOn: $isActive)
                    }
                    .glassCard()

                    if let error { ErrorBanner(message: error) }

                    Button {
                        Task { await save() }
                    } label: {
                        LoadingLabel(title: existing == nil ? "Add employee" : "Save changes", systemImage: "checkmark.circle.fill", isLoading: isSaving)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(!isValid || isSaving)
                }
                .padding(GlassMetrics.screenPadding)
            }
            .glassScreen()
            .navigationTitle(existing == nil ? "New employee" : "Edit employee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            mobile = existing.mobile
            code = existing.employeeCode
            branchId = existing.branchId
            isActive = existing.isActive
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        let rawMobile = mobile.trimmingCharacters(in: .whitespaces)
        let input = EmployeeInput(
            name: name.trimmingCharacters(in: .whitespaces),
            mobile: rawMobile.hasPrefix("+") ? "+" + mobileDigits : mobileDigits,
            employeeCode: code.trimmingCharacters(in: .whitespaces),
            branchId: branchId,
            isActive: isActive
        )
        do {
            let saved: AdminEmployee
            if let existing {
                saved = try await session.api.updateEmployee(existing.id, input)
            } else {
                saved = try await session.api.createEmployee(input)
            }
            onSaved(saved)
            toasts.success(existing == nil ? "\(saved.name) can now sign in with OTP" : "Employee updated")
            dismiss()
        } catch {
            self.error = APIError.from(error).message
        }
    }
}
