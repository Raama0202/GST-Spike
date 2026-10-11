import Foundation

struct APICredentials: Sendable {
    var accessToken: String?
    var companyId: String?
}

/// Serialises concurrent refresh attempts so a burst of 401s triggers a
/// single `/auth/token/refresh` call.
private actor RefreshGate {
    private var inFlight: Task<Bool, Never>?

    func run(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
        if let inFlight { return await inFlight.value }
        let task = Task { await operation() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

/// URLSession client shared by both apps. Mirrors the Flutter Dio setup:
/// bearer token, `X-Company-Id`, `X-Device-Id`, one transparent refresh on
/// 401, and long timeouts because free Render instances cold-start slowly.
final class APIClient: @unchecked Sendable {
    enum Method: String {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    typealias CredentialsProvider = @Sendable () -> APICredentials
    typealias Refresher = @Sendable () async -> Bool

    static let refreshPath = "/auth/token/refresh"

    private let session: URLSession
    private let credentials: CredentialsProvider
    private let deviceId: String
    private let gate = RefreshGate()
    private var refresher: Refresher?

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    init(deviceId: String, credentials: @escaping CredentialsProvider) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)
        self.deviceId = deviceId
        self.credentials = credentials
    }

    /// Installed once at start-up by the session owner.
    func setRefresher(_ refresher: @escaping Refresher) {
        self.refresher = refresher
    }

    // MARK: - Typed helpers

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await raw(.get, path, query: query)
        return try decode(type, from: data)
    }

    func send<T: Decodable>(
        _ method: Method,
        _ path: String,
        json: (any Encodable)? = nil,
        query: [String: String?] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        let body = try json.map { try encoder.encode($0) }
        let data = try await raw(method, path, query: query, body: body)
        return try decode(type, from: data)
    }

    func sendVoid(_ method: Method, _ path: String, json: (any Encodable)? = nil, query: [String: String?] = [:]) async throws {
        let body = try json.map { try encoder.encode($0) }
        _ = try await raw(method, path, query: query, body: body)
    }

    func upload<T: Decodable>(_ path: String, form: MultipartForm, timeout: TimeInterval = 120, as type: T.Type = T.self) async throws -> T {
        let data = try await raw(.post, path, body: form.finalized(), contentType: form.contentType, timeout: timeout)
        return try decode(type, from: data)
    }

    // MARK: - Transport

    func raw(
        _ method: Method,
        _ path: String,
        query: [String: String?] = [:],
        body: Data? = nil,
        contentType: String? = "application/json",
        timeout: TimeInterval = 90,
        authenticated: Bool = true,
        allowRefresh: Bool = true
    ) async throws -> Data {
        let request = try makeRequest(method, path, query: query, body: body, contentType: contentType, timeout: timeout, authenticated: authenticated)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.from(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(kind: .unknown, status: nil, message: "Invalid server response.")
        }

        if http.statusCode == 401, authenticated, allowRefresh, !path.hasPrefix(Self.refreshPath), let refresher {
            if await gate.run(refresher) {
                return try await raw(method, path, query: query, body: body, contentType: contentType, timeout: timeout, authenticated: authenticated, allowRefresh: false)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(
                status: http.statusCode,
                data: data,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
        return data
    }

    private func makeRequest(
        _ method: Method,
        _ path: String,
        query: [String: String?],
        body: Data?,
        contentType: String?,
        timeout: TimeInterval,
        authenticated: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(string: ServerConfig.baseURL + path) else {
            throw APIError(kind: .unknown, status: nil, message: "Invalid API URL: \(ServerConfig.baseURL)")
        }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components.url else {
            throw APIError(kind: .unknown, status: nil, message: "Invalid API URL: \(ServerConfig.baseURL)")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        if let body {
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        if authenticated {
            let creds = credentials()
            if let token = creds.accessToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let companyId = creds.companyId, !companyId.isEmpty {
                request.setValue(companyId, forHTTPHeaderField: "X-Company-Id")
            }
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.from(error)
        }
    }
}

/// Decodes 204 / ignorable bodies.
struct EmptyResponse: Decodable {}

/// Generic `{ "items": [...] }` envelope used by every list endpoint.
struct ItemsResponse<T: Decodable>: Decodable {
    let items: [T]
    /// Present on paginated endpoints; nil when the server returned the full list.
    let total: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        items = (try? container.decode([FailableDecodable<T>].self, forKey: "items"))?.compactMap(\.value) ?? []
        total = try? container.decode(Int.self, forKey: "total")
    }
}

/// Skips individual malformed rows instead of failing a whole list.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
