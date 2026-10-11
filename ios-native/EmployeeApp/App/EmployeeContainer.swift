import Foundation
import Observation

/// Composition root for the employee app (the Riverpod `providers.dart`
/// equivalent). One instance lives for the whole process.
@MainActor
@Observable
final class EmployeeContainer {
    static let shared = EmployeeContainer()

    let sessionStore: SessionStore
    let api: APIClient
    let invoiceStore: InvoiceStore
    let remote: InvoiceRemote
    let config: CompanyConfigModel
    let notifications: NotificationsModel
    let sync: SyncEngine
    let session: SessionModel
    let toasts: ToastCenter
    let extractor: InvoiceExtractor
    let pipeline: ImagePipeline
    let location: LocationProvider

    private init() {
        let sessionStore = SessionStore()
        let api = APIClient(deviceId: sessionStore.deviceId) { sessionStore.credentials() }
        let refresher = TokenRefresher(api: api, store: sessionStore)
        api.setRefresher { await refresher.refresh() }

        let invoiceStore = InvoiceStore()
        let remote = InvoiceRemote(api: api)
        let config = CompanyConfigModel(api: api)
        let notifications = NotificationsModel(api: api)
        let sync = SyncEngine(store: invoiceStore, remote: remote, config: config, notifications: notifications, sessionStore: sessionStore)

        self.sessionStore = sessionStore
        self.api = api
        self.invoiceStore = invoiceStore
        self.remote = remote
        self.config = config
        self.notifications = notifications
        self.sync = sync
        self.session = SessionModel(api: api, store: sessionStore, invoices: invoiceStore, config: config, notifications: notifications, sync: sync)
        self.toasts = ToastCenter()
        self.extractor = InvoiceExtractor(api: api)
        self.pipeline = ImagePipeline()
        self.location = LocationProvider()
    }
}
