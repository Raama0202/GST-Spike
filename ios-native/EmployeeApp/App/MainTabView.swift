import SwiftUI

enum EmployeeTab: Hashable {
    case home, uploads, alerts, profile
}

/// Glass tab shell. Tabs stay alive (opacity switch) so each keeps its own
/// navigation stack and scroll position.
struct MainTabView: View {
    @Environment(NotificationsModel.self) private var notifications
    @State private var selection: EmployeeTab = .home
    @State private var showScanner = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tab(.home) { HomeView(selection: $selection, showScanner: $showScanner) }
                tab(.uploads) { UploadsView() }
                tab(.alerts) { NotificationsView() }
                tab(.profile) { ProfileView() }
            }

            FloatingTabBar(
                items: [
                    TabItem(id: EmployeeTab.home, title: "Home", systemImage: "house"),
                    TabItem(id: EmployeeTab.uploads, title: "Uploads", systemImage: "tray.full"),
                    TabItem(id: EmployeeTab.alerts, title: "Alerts", systemImage: "bell", badge: notifications.unreadCount),
                    TabItem(id: EmployeeTab.profile, title: "Profile", systemImage: "person.crop.circle"),
                ],
                selection: $selection,
                centerAction: (systemImage: "doc.viewfinder", action: { showScanner = true })
            )
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showScanner) {
            ScanFlowView()
        }
    }

    @ViewBuilder
    private func tab<Content: View>(_ id: EmployeeTab, @ViewBuilder content: () -> Content) -> some View {
        let active = selection == id
        content()
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: GlassMetrics.tabBarClearance) }
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}
