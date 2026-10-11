import Foundation
import Network
import Observation

/// Processes the offline upload queue with exponential backoff — a port of
/// the Android `SyncEngine`. Idempotency key = local UUID, so a replayed
/// upload returns the same server invoice instead of creating a duplicate.
@MainActor
@Observable
final class SyncEngine {
    private(set) var isSyncing = false
    private(set) var pendingCount = 0
    private(set) var todayCount = 0
    private(set) var lastError: String? = nil
    private(set) var lastSyncedAt: Date? = nil
    private(set) var isOnline = true
    /// Bumped whenever stored invoices change so lists can reload.
    private(set) var revision = 0

    private let store: InvoiceStore
    private let remote: InvoiceRemote
    private let config: CompanyConfigModel
    private let notifications: NotificationsModel
    private let sessionStore: SessionStore

    @ObservationIgnored private var loopTask: Task<Void, Never>? = nil
    @ObservationIgnored private var activeRun: Task<Void, Never>? = nil
    @ObservationIgnored private let monitor = NWPathMonitor()

    init(store: InvoiceStore, remote: InvoiceRemote, config: CompanyConfigModel, notifications: NotificationsModel, sessionStore: SessionStore) {
        self.store = store
        self.remote = remote
        self.config = config
        self.notifications = notifications
        self.sessionStore = sessionStore

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cameOnline = online && !self.isOnline
                self.isOnline = online
                if cameOnline, self.loopTask != nil { await self.syncNow() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "gst.sync.path"))
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.store.recoverStuckUploads()
            while !Task.isCancelled, let engine = self {
                await engine.runOnce(fullRefresh: false)
                try? await Task.sleep(for: .seconds(EmployeeConstants.syncLoopInterval))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isSyncing = false
    }

    /// Manual "Sync Now": uploads the queue, then pulls statuses, config and
    /// notifications from the dashboard.
    func syncNow() async {
        await runOnce(fullRefresh: true)
    }

    func refreshCounts() async {
        pendingCount = await store.pendingCount()
        todayCount = await store.todayCount()
        revision += 1
    }

    private func runOnce(fullRefresh: Bool) async {
        if let activeRun {
            await activeRun.value
            if !fullRefresh { return }
        }
        let run = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
            if fullRefresh || self.pendingCount == 0 {
                await self.pullFromDashboard()
            }
        }
        activeRun = run
        await run.value
        activeRun = nil
    }

    private func processQueue() async {
        let queue = await store.queued()
        guard !queue.isEmpty else {
            await refreshCounts()
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        var hadFailure = false
        for invoice in queue where isReady(invoice) {
            if Task.isCancelled { break }
            if await upload(invoice) == false { hadFailure = true }
            await refreshCounts()
        }
        if !hadFailure {
            lastError = nil
            lastSyncedAt = Date()
            await config.refresh()
        }
    }

    private func pullFromDashboard() async {
        guard let employee = sessionStore.employee else { return }
        if let items = try? await remote.mine() {
            let changes = await store.merge(remote: items, employee: employee)
            if changes > 0 { await refreshCounts() }
        }
        await notifications.refresh()
        LocalNotifier.setBadge(notifications.unreadCount)
    }

    private func isReady(_ invoice: LocalInvoice) -> Bool {
        guard let next = invoice.nextAttemptAt else { return true }
        return next <= Date()
    }

    /// Returns `true` when the invoice reached the server.
    private func upload(_ invoice: LocalInvoice) async -> Bool {
        var working = invoice
        working.idempotencyKey = invoice.idempotencyKey ?? invoice.localId

        let compressed = await store.imageData(invoice.compressedImageFile)
        let original = await store.imageData(invoice.originalImageFile)
        let thumbnail = await store.imageData(invoice.thumbnailFile)
        guard let primary = compressed ?? original else {
            await markFailed(working, error: "Missing invoice image for upload.", retryable: false)
            return false
        }

        working.syncStatus = .uploading
        await store.save(working)

        do {
            let response = try await remote.upload(
                working,
                original: original ?? primary,
                compressed: primary,
                thumbnail: thumbnail ?? primary
            )
            working.serverId = response.id
            working.syncStatus = .uploaded
            working.approvalStatus = .uploaded
            working.uploadedAt = Date()
            working.uploadAttempts = invoice.uploadAttempts + 1
            working.lastUploadError = nil
            working.isQueued = false
            working.nextAttemptAt = nil
            await store.save(working)
            return true
        } catch {
            let apiError = APIError.from(error)
            // A 409 means the server already flagged this as a duplicate and the
            // employee did not override; retrying would loop forever.
            let retryable = apiError.kind != .conflict && apiError.kind != .validation && apiError.kind != .forbidden
            await markFailed(working, error: apiError.message, retryable: retryable)
            lastError = apiError.message
            return false
        }
    }

    private func markFailed(_ invoice: LocalInvoice, error: String, retryable: Bool) async {
        var updated = invoice
        let attempts = invoice.uploadAttempts + 1
        updated.uploadAttempts = attempts
        updated.lastUploadError = error

        if !retryable || attempts >= EmployeeConstants.syncMaxAttempts {
            updated.syncStatus = .failed
            updated.nextAttemptAt = nil
        } else {
            updated.syncStatus = .pending
            let multiplier = pow(2.0, Double(min(max(attempts - 1, 0), 10)))
            updated.nextAttemptAt = Date().addingTimeInterval(EmployeeConstants.syncBaseBackoff * multiplier)
        }
        await store.save(updated)
    }

    /// "Retry" on a failed upload resets its attempt budget and re-queues it.
    func retry(_ localId: String) async {
        guard var invoice = await store.get(localId) else { return }
        invoice.syncStatus = .pending
        invoice.isQueued = true
        invoice.uploadAttempts = 0
        invoice.nextAttemptAt = nil
        invoice.lastUploadError = nil
        await store.save(invoice)
        await refreshCounts()
        await syncNow()
    }
}
