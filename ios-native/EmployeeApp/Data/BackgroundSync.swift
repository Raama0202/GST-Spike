import BackgroundTasks
import Foundation

/// iOS counterpart of the Android WorkManager periodic task.
enum BackgroundSync {
    private static var handler: (@MainActor () async -> Void)?

    /// Must be called before the app finishes launching.
    static func register(_ work: @escaping @MainActor () async -> Void) {
        handler = work
        BGTaskScheduler.shared.register(forTaskWithIdentifier: EmployeeConstants.backgroundTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let job = Task { @MainActor in
                await handler?()
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = {
                job.cancel()
                refresh.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: EmployeeConstants.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
