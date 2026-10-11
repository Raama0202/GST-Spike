import Foundation

/// Error surfaced to the UI. The API's error shape is `{ "message": "..." }`.
struct APIError: LocalizedError, Equatable {
    enum Kind: Equatable {
        case offline
        case timeout
        case unauthorized
        case forbidden
        case notFound
        case conflict
        case validation
        case rateLimited
        case server
        case decoding
        case unknown
    }

    let kind: Kind
    let status: Int?
    let message: String

    var errorDescription: String? { message }

    /// Network-level problems that the sync queue should retry later.
    var isRetryable: Bool {
        switch kind {
        case .offline, .timeout, .server, .rateLimited, .unauthorized: return true
        default: return false
        }
    }

    static func from(status: Int, data: Data, retryAfter: String? = nil) -> APIError {
        var message = Self.serverMessage(data) ?? Self.defaultMessage(status)
        if status == 429, let seconds = retryAfter.flatMap(Int.init), seconds > 0 {
            message = "Too many requests. Please wait \(seconds) seconds and try again."
        } else if status >= 500, ![502, 503, 504].contains(status),
                  let requestId = Self.requestId(data) {
            message += " (ref \(requestId))"
        }
        let kind: Kind
        switch status {
        case 400, 422: kind = .validation
        case 401: kind = .unauthorized
        case 403: kind = .forbidden
        case 404: kind = .notFound
        case 409: kind = .conflict
        case 429: kind = .rateLimited
        case 500...599: kind = .server
        default: kind = .unknown
        }
        return APIError(kind: kind, status: status, message: message)
    }

    static func from(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut:
                return APIError(kind: .timeout, status: nil, message: "The server took too long to respond. It may be waking up — please try again.")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return APIError(kind: .offline, status: nil, message: "Cannot reach the server. Check the API URL and your connection.")
            case .cancelled:
                return APIError(kind: .unknown, status: nil, message: "Request cancelled.")
            default:
                return APIError(kind: .offline, status: nil, message: url.localizedDescription)
            }
        }
        if error is DecodingError {
            return APIError(kind: .decoding, status: nil, message: "Unexpected response from the server.")
        }
        return APIError(kind: .unknown, status: nil, message: error.localizedDescription)
    }

    private static func serverMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["message"] as? String, !message.isEmpty {
            if message == "Invalid request", let errors = object["errors"] as? [[String: Any]],
               let first = errors.first, let detail = first["msg"] as? String {
                let field = (first["loc"] as? [Any])?.last.map { "\($0)" }
                return field.map { "\($0): \(detail)" } ?? detail
            }
            return message
        }
        if let detail = object["detail"] as? String { return detail }
        return nil
    }

    private static func requestId(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["requestId"] as? String
    }

    private static func defaultMessage(_ status: Int) -> String {
        switch status {
        case 401: return "Your session has expired. Please sign in again."
        case 403: return "You do not have access to this resource."
        case 404: return "Not found."
        case 413: return "That file is too large to upload."
        case 429: return "Too many requests. Please wait a moment."
        case 502, 503, 504: return "The service is temporarily unavailable. Try again shortly."
        case 500...599: return "Server error (\(status)). Please try again shortly."
        default: return "Request failed (\(status))."
        }
    }
}
