import SwiftUI

struct AdminProfileView: View {
    @Environment(AdminSession.self) private var session
    @State private var confirmSignOut = false
    @State private var showServer = false
    @State private var signingOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    AvatarView(name: session.user?.email ?? "A", size: 84)
                    Text(session.user?.email ?? "")
                        .font(.display(20, weight: .bold))
                    Text(session.user?.role.title ?? "")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(session.user?.role == .superAdmin ? Brand.violet.gradient : Brand.indigo.gradient))
                }
                .frame(maxWidth: .infinity)
                .glassCard(padding: 24)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "App")
                    DetailRow(label: "Version", value: AppInfo.version, systemImage: "info.circle")
                    GlassDivider()
                    if ServerConfig.canOverride {
                        Button { showServer = true } label: {
                            HStack {
                                DetailRow(label: "Server", value: ServerConfig.displayHost, systemImage: "server.rack")
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        DetailRow(label: "Server", value: ServerConfig.displayHost, systemImage: "server.rack")
                    }
                    GlassDivider()
                    DetailRow(label: "Device", value: String(session.store.deviceId.prefix(8)), systemImage: "iphone")
                }
                .glassCard()

                Button {
                    confirmSignOut = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.glassSecondary(tint: Brand.danger))
            }
            .padding(GlassMetrics.screenPadding)
        }
        .glassScreen()
        .navigationTitle("Account")
        .sheet(isPresented: $showServer) {
            ServerEndpointSheet()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Sign out of the admin app?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    signingOut = true
                    await session.logout()
                    signingOut = false
                }
            }
        }
        .overlay { LoadingOverlay(isVisible: signingOut, message: "Signing out…") }
    }
}
