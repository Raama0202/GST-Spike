import Foundation

/// The API endpoint in use. Mirrors `ServerConfig` in both Flutter apps:
/// compiled default from the build setting `API_BASE_URL`, optional runtime
/// override when `ALLOW_SERVER_OVERRIDE` is `YES` (demo / on-prem builds).
enum ServerConfig {
    static let fallbackBaseURL = "https://gst-expense-scanner.onrender.com/v1"
    private static let overrideKey = "api_base_url_override"

    static var compiledBaseURL: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty, !value.contains("$("), let normalized = normalize(value) else {
            return fallbackBaseURL
        }
        return normalized
    }

    static var canOverride: Bool {
        let flag = (Bundle.main.object(forInfoDictionaryKey: "ALLOW_SERVER_OVERRIDE") as? String)?.uppercased()
        return flag == "YES" || flag == "TRUE" || flag == "1"
    }

    static var baseURL: String {
        guard canOverride,
              let saved = UserDefaults.standard.string(forKey: overrideKey),
              let normalized = normalize(saved)
        else { return compiledBaseURL }
        return normalized
    }

    static var isOverridden: Bool { baseURL != compiledBaseURL }

    static var displayHost: String { URL(string: baseURL)?.host ?? baseURL }

    @discardableResult
    static func save(_ input: String) -> String? {
        guard canOverride, let normalized = normalize(input) else { return nil }
        UserDefaults.standard.set(normalized, forKey: overrideKey)
        return normalized
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    /// Accepts a bare host, host:port or full URL and returns a canonical API
    /// base URL. A bare host is assumed to mean the versioned `/v1` root.
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }

        components.scheme = scheme
        components.path = path
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }

    /// Local-storage images come back as signed `/v1/media/...` paths relative
    /// to the server root; R2 presigned URLs are already absolute.
    static func absoluteURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        guard let base = URLComponents(string: baseURL) else { return nil }
        var origin = URLComponents()
        origin.scheme = base.scheme
        origin.host = base.host
        origin.port = base.port
        guard let originURL = origin.url else { return nil }
        return URL(string: path, relativeTo: originURL)?.absoluteURL
    }
}
