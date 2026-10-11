import SwiftUI

struct AdminLoginView: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showActivation = false
    @State private var showServer = false
    @State private var appeared = false

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6 && !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                hero
                form
                footer
            }
            .padding(.horizontal, GlassMetrics.screenPadding)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(GlassBackground())
        .sheet(isPresented: $showActivation) {
            ActivateCompanySheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showServer) {
            ServerEndpointSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if email.isEmpty { email = session.store.lastEmail ?? "" }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AppLogo(systemImage: "chart.bar.doc.horizontal.fill", size: 88)
            Text("Admin Console")
                .font(.display(32, weight: .heavy))
            Text("Review invoices, reconcile ITC and manage your team — wherever you are.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private var form: some View {
        VStack(spacing: 16) {
            GlassTextField(title: "Work email", text: $email, systemImage: "envelope.fill", prompt: "admin@company.com", keyboard: .emailAddress, capitalization: .never)
                .textContentType(.username)
            GlassTextField(title: "Password", text: $password, systemImage: "lock.fill", prompt: "••••••••", capitalization: .never, isSecure: true)
                .textContentType(.password)
                .onSubmit { Task { await submit() } }

            if let error {
                ErrorBanner(message: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button {
                Task { await submit() }
            } label: {
                LoadingLabel(title: "Sign in", systemImage: "arrow.right.circle.fill", isLoading: isLoading)
            }
            .buttonStyle(.glassPrimary)
            .disabled(!canSubmit)
        }
        .glassCard(padding: 22)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
        .animation(.default, value: error)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                showActivation = true
            } label: {
                Label("Activate a new company", systemImage: "key.horizontal.fill")
                    .font(.subheadline.weight(.semibold))
            }
            if ServerConfig.canOverride {
                Button {
                    showServer = true
                } label: {
                    Label(ServerConfig.displayHost, systemImage: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Version \(AppInfo.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 30)
    }

    private func submit() async {
        guard canSubmit else { return }
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.login(email: email, password: password)
            password = ""
        } catch {
            self.error = APIError.from(error).message
        }
    }
}

/// Public `/super/companies/activate` — companies created by the super admin
/// start as `pending` until the activation code is redeemed.
struct ActivateCompanySheet: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                IconBadge(systemImage: "key.horizontal.fill", color: Brand.violet, size: 56)
                Text("Enter the activation code shared by your platform administrator.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GlassTextField(title: "Activation code", text: $code, systemImage: "number", prompt: "e.g. aB3xY9kQ_2", capitalization: .never)
                if let error { ErrorBanner(message: error) }
                Button {
                    Task { await activate() }
                } label: {
                    LoadingLabel(title: "Activate", systemImage: "checkmark.seal.fill", isLoading: isLoading)
                }
                .buttonStyle(.glassPrimary)
                .disabled(code.nilIfBlank == nil || isLoading)
                Spacer()
            }
            .padding(GlassMetrics.screenPadding)
            .glassScreen()
            .navigationTitle("Activate company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func activate() async {
        guard let value = code.nilIfBlank else { return }
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await session.api.activateCompany(code: value)
            toasts.success("Company activated — sign in with the admin credentials")
            dismiss()
        } catch {
            self.error = APIError.from(error).message
        }
    }
}
