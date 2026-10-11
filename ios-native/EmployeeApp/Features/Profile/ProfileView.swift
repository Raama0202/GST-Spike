import SwiftUI

struct ProfileView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CompanyConfigModel.self) private var config
    @Environment(SyncEngine.self) private var sync

    @State private var confirmSignOut = false
    @State private var showServer = false
    @State private var signingOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    detailsCard
                    syncCard
                    appCard
                    signOutButton
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .glassScreen()
            .navigationTitle("Profile")
        }
        .sheet(isPresented: $showServer) {
            ServerEndpointSheet()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Sign out?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task {
                    signingOut = true
                    await session.logout()
                    signingOut = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if sync.pendingCount > 0 {
                Text("\(sync.pendingCount) invoice(s) have not been uploaded yet and will be deleted from this device. Connect to the internet and sync first to keep them.")
            } else {
                Text("Local invoice data on this device will be cleared.")
            }
        }
        .overlay { LoadingOverlay(isVisible: signingOut, message: "Signing out…") }
    }

    private var header: some View {
        VStack(spacing: 12) {
            AvatarView(name: session.employee?.name ?? "?", size: 84)
            VStack(spacing: 4) {
                Text(session.employee?.name ?? "Employee")
                    .font(.display(24, weight: .bold))
                Text(config.config?.companyName ?? session.employee?.companyName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 24)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Account")
            DetailRow(label: "Mobile", value: session.employee?.mobile ?? "—", systemImage: "phone.fill")
            GlassDivider()
            DetailRow(label: "Employee code", value: session.employee?.employeeCode.nilIfBlank ?? "—", systemImage: "person.text.rectangle")
            GlassDivider()
            DetailRow(label: "Branch", value: session.employee?.branchName ?? "—", systemImage: "mappin.and.ellipse")
            if let industry = config.config?.industry.nilIfBlank {
                GlassDivider()
                DetailRow(label: "Industry", value: industry.humanizedKey, systemImage: "building.2")
            }
        }
        .glassCard()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sync")
            DetailRow(
                label: "Connection",
                value: sync.isOnline ? "Online" : "Offline",
                systemImage: sync.isOnline ? "wifi" : "wifi.slash",
                valueColor: sync.isOnline ? Brand.success : Brand.warning
            )
            GlassDivider()
            DetailRow(label: "Waiting to upload", value: "\(sync.pendingCount)", systemImage: "icloud.and.arrow.up")
            GlassDivider()
            DetailRow(label: "Last synced", value: Formatters.relativeString(sync.lastSyncedAt), systemImage: "clock.arrow.circlepath")
            Button {
                Task { await sync.syncNow() }
            } label: {
                LoadingLabel(title: "Sync now", systemImage: "arrow.triangle.2.circlepath", isLoading: sync.isSyncing)
            }
            .buttonStyle(.glassSecondary)
            .disabled(sync.isSyncing)
        }
        .glassCard()
    }

    private var appCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "App")
            DetailRow(label: "Version", value: AppInfo.version, systemImage: "info.circle")
            GlassDivider()
            if ServerConfig.canOverride {
                Button { showServer = true } label: {
                    HStack {
                        DetailRow(label: "Server", value: ServerConfig.displayHost, systemImage: "server.rack")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                DetailRow(label: "Server", value: ServerConfig.displayHost, systemImage: "server.rack")
            }
        }
        .glassCard()
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                .foregroundStyle(Brand.danger)
        }
        .buttonStyle(.glassSecondary(tint: Brand.danger))
        .padding(.bottom, 24)
    }
}
