import SwiftUI

struct NotificationsView: View {
    @Environment(NotificationsModel.self) private var notifications
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = notifications.lastError, notifications.items.isEmpty {
                        ErrorBanner(message: error) { Task { await notifications.refresh(announceNew: false) } }
                    }
                    if notifications.items.isEmpty {
                        if notifications.isLoading {
                            ForEach(0..<4, id: \.self) { _ in ShimmerRow() }
                        } else {
                            EmptyStateView(
                                systemImage: "bell.slash",
                                title: "You're all caught up",
                                message: "Approvals, returns and company announcements will appear here."
                            )
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(notifications.items) { item in
                                NotificationRow(item: item)
                                    .onTapGesture {
                                        Task { await notifications.markRead([item.id]) }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenPadding)
                .padding(.top, 8)
            }
            .refreshable { await notifications.refresh(announceNew: false) }
            .glassScreen()
            .navigationTitle("Alerts")
            .toolbar {
                if notifications.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await notifications.markAllRead()
                                LocalNotifier.setBadge(0)
                            }
                        } label: {
                            Label("Mark all read", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
        }
        .task { await notifications.refresh(announceNew: false) }
    }
}

private struct NotificationRow: View {
    let item: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemImage: item.style.systemImage, color: item.style.color, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(item.read ? .medium : .bold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(Formatters.relativeString(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            if !item.read {
                Circle()
                    .fill(item.style.color)
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16, tint: item.read ? nil : item.style.color)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: item.read)
    }
}
