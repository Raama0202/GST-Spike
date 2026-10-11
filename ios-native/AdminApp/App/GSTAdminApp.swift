import SwiftUI

@main
struct GSTAdminApp: App {
    @State private var session = AdminSession()
    @State private var toasts = ToastCenter()

    var body: some Scene {
        WindowGroup {
            AdminRootView()
                .environment(session)
                .environment(toasts)
        }
    }
}

struct AdminRootView: View {
    @Environment(AdminSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ZStack {
            switch session.state {
            case .launching:
                AdminSplashView()
                    .transition(.opacity)
            case .signedOut:
                AdminLoginView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .signedIn:
                CompanyAdminShell()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.smooth(duration: 0.4), value: session.state)
        .brand(Brand.indigo)
        .toastHost(toasts)
        .task { await session.restore() }
    }
}

struct AdminSplashView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            AppLogo(systemImage: "chart.bar.doc.horizontal.fill", size: 92)
                .scaleEffect(pulse ? 1.05 : 0.95)
            Text("GST Expense Admin")
                .font(.display(26, weight: .bold))
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
