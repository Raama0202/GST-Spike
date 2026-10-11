import SwiftUI

@main
struct GSTScannerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container = EmployeeContainer.shared

    init() {
        BackgroundSync.register {
            let container = EmployeeContainer.shared
            guard container.session.isSignedIn else { return }
            await container.sync.syncNow()
        }
    }

    var body: some Scene {
        WindowGroup {
            EmployeeRootView()
                .environment(container)
                .environment(container.session)
                .environment(container.config)
                .environment(container.sync)
                .environment(container.notifications)
                .environment(container.toasts)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard container.session.isSignedIn else { return }
                container.sync.start()
                Task { await container.sync.syncNow() }
            case .background:
                container.sync.stop()
                BackgroundSync.schedule()
            default:
                break
            }
        }
    }
}

struct EmployeeRootView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CompanyConfigModel.self) private var config
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ZStack {
            switch session.state {
            case .launching:
                SplashView()
                    .transition(.opacity)
            case .signedOut:
                LoginFlowView()
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            case .signedIn:
                MainTabView()
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            }
        }
        .brand(config.brandColor)
        .toastHost(toasts)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: session.state)
        .task { await session.restore() }
    }
}
