import Foundation

/// Same paths as `ApiEndpoints` in the Android employee app.
enum EmployeeEndpoints {
    static let requestOtp = "/auth/otp/request"
    static let verifyOtp = "/auth/otp/verify"
    static let refreshToken = "/auth/token/refresh"
    static let logout = "/auth/logout"
    static let me = "/employees/me"
    static let companyConfig = "/company/config"
    static let duplicateCheck = "/invoices/duplicate-check"
    static let upload = "/invoices/upload"
    static let extract = "/invoices/extract"
    static let extractStatus = "/invoices/extract/status"
    static let mine = "/invoices/mine"
    static let notifications = "/notifications"
    static let markRead = "/notifications/read"
    static let deviceRegister = "/devices/register"
}

enum EmployeeConstants {
    static let otpLength = 6
    static let otpResendSeconds = 30
    static let maxUploadImageBytes = 1024 * 1024
    static let thumbnailMaxEdge: CGFloat = 320
    static let blurVarianceThreshold = 80.0
    static let lowOcrConfidenceThreshold = 0.55
    static let syncMaxAttempts = 8
    static let syncBaseBackoff: TimeInterval = 2
    static let syncLoopInterval: TimeInterval = 15
    static let backgroundTaskId = "com.gstexpenses.gstexpensescanner.sync"
}

extension Notification.Name {
    static let employeeSessionExpired = Notification.Name("employeeSessionExpired")
}
