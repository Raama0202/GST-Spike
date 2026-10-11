import Foundation
import Observation
import UserNotifications

/// Status notifications via API polling + local notifications, same as the
/// Android app (no hard APNs/FCM dependency).
@MainActor
@Observable
final class NotificationsModel {
    private(set) var items: [AppNotification] = []
    private(set) var isLoading = false
    private(set) var lastError: String? = nil

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var companyId: String? = nil
    @ObservationIgnored private var announcedIds: Set<String> = []

    init(api: APIClient) {
        self.api = api
    }

    var unreadCount: Int { items.filter { !$0.read }.count }

    func activate(companyId: String?) {
        self.companyId = companyId
        guard let companyId else {
            items = []
            announcedIds = []
            return
        }
        items = TenantStorage.read([AppNotification].self, from: cacheURL(companyId)) ?? []
        announcedIds = Set(items.map(\.id))
    }

    func refresh(announceNew: Bool = true) async {
        guard let companyId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ItemsResponse<AppNotification> = try await api.get(EmployeeEndpoints.notifications)
            let fresh = response.items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            let newUnread = fresh.filter { !$0.read && !announcedIds.contains($0.id) }
            items = fresh
            lastError = nil
            TenantStorage.save(fresh, to: cacheURL(companyId))
            // The first fetch after login only seeds the baseline; it never alerts.
            if announceNew, !announcedIds.isEmpty, !newUnread.isEmpty {
                LocalNotifier.post(newUnread.prefix(3).map { (id: $0.id, title: $0.title, body: $0.body) })
            }
            announcedIds.formUnion(fresh.map(\.id))
        } catch {
            lastError = APIError.from(error).message
        }
    }

    func markRead(_ ids: [String]) async {
        let unread = ids.filter { id in items.contains { $0.id == id && !$0.read } }
        guard !unread.isEmpty else { return }
        items = items.map { item in
            var copy = item
            if unread.contains(item.id) { copy.read = true }
            return copy
        }
        if let companyId { TenantStorage.save(items, to: cacheURL(companyId)) }
        struct Body: Encodable { let ids: [String] }
        try? await api.sendVoid(.post, EmployeeEndpoints.markRead, json: Body(ids: unread))
    }

    func markAllRead() async {
        await markRead(items.filter { !$0.read }.map(\.id))
    }

    private func cacheURL(_ companyId: String) -> URL {
        TenantStorage.directory(companyId).appendingPathComponent("notifications.json")
    }
}

enum LocalNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    static func post(_ entries: [(id: String, title: String, body: String)]) {
        let center = UNUserNotificationCenter.current()
        for entry in entries {
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = entry.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: "notification-\(entry.id)", content: content, trigger: nil)
            center.add(request)
        }
    }

    static func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }
}
