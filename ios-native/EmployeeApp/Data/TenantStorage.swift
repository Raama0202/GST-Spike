import Foundation

/// File layout namespaced by `companyId` so re-login to a different tenant on
/// the same device can never surface rows from the previous one (the iOS
/// equivalent of the per-tenant Hive boxes).
///
///     Application Support/tenants/<companyId>/invoices.json
///     Application Support/tenants/<companyId>/config.json
///     Application Support/tenants/<companyId>/notifications.json
///     Application Support/tenants/<companyId>/images/<localId>_compressed.jpg
enum TenantStorage {
    private static let fileManager = FileManager.default

    static var root: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tenants", isDirectory: true)
    }

    static func directory(_ companyId: String) -> URL {
        let url = root.appendingPathComponent(safe(companyId), isDirectory: true)
        ensureDirectory(url)
        return url
    }

    static func imagesDirectory(_ companyId: String) -> URL {
        let url = directory(companyId).appendingPathComponent("images", isDirectory: true)
        ensureDirectory(url)
        return url
    }

    static func imageURL(companyId: String, file: String?) -> URL? {
        guard let file, !file.isEmpty else { return nil }
        let url = imagesDirectory(companyId).appendingPathComponent(file)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes with complete-until-first-unlock protection so background
    /// sync can still read queued images while the device is locked.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? write(data, to: url)
    }

    static func wipe(_ companyId: String) {
        try? fileManager.removeItem(at: root.appendingPathComponent(safe(companyId), isDirectory: true))
    }

    static func wipeAll() {
        try? fileManager.removeItem(at: root)
    }

    private static func ensureDirectory(_ url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static func safe(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    }
}
