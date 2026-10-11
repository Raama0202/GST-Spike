import Foundation

/// The FastAPI backend emits UUIDs as strings, Decimals as numbers and
/// datetimes with or without fractional seconds / timezone depending on the
/// database. These helpers decode all of those variants without failing.
extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return JSONValue.number(value).stringValue
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func string(_ keys: Key...) -> String? {
        for key in keys { if let value = string(key) { return value } }
        return nil
    }

    func double(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    func double(_ keys: Key...) -> Double? {
        for key in keys { if let value = double(key) { return value } }
        return nil
    }

    func int(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = double(key) { return Int(value) }
        return nil
    }

    func bool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "yes", "1"].contains(value.lowercased())
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return nil
    }

    func bool(_ keys: Key...) -> Bool? {
        for key in keys { if let value = bool(key) { return value } }
        return nil
    }

    func date(_ key: Key) -> Date? {
        if let raw = try? decodeIfPresent(String.self, forKey: key) { return DateParser.parse(raw) }
        if let seconds = try? decodeIfPresent(Double.self, forKey: key) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    func json(_ key: Key) -> JSONValue? {
        guard let value = try? decodeIfPresent(JSONValue.self, forKey: key) else { return nil }
        return value
    }
}

/// Lets models declare keys as plain strings (`AnyKey("vendorName")`).
struct AnyKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    init(stringLiteral value: String) { stringValue = value }
}

enum DateParser {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Naive timestamps (no zone) from the API are UTC.
    private static let naiveFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSSSSS",
        "yyyy-MM-dd HH:mm:ss",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    /// Calendar dates (`2026-03-15`) are interpreted in the device zone so
    /// they display as the same day the bill shows.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let date = isoFractional.date(from: raw) ?? iso.date(from: raw) { return date }
        // Python can emit microseconds with an offset, which ISO8601DateFormatter rejects.
        if let normalized = trimMicroseconds(raw), let date = isoFractional.date(from: normalized) { return date }
        for formatter in naiveFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        if raw.count >= 10, let date = dayFormatter.date(from: String(raw.prefix(10))) { return date }
        return nil
    }

    /// Calendar-date fields (invoice dates) ignore any time component so the
    /// bill date never shifts across time zones.
    static func parseDay(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 10 else { return parse(raw) }
        return dayFormatter.date(from: String(raw.prefix(10))) ?? parse(raw)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func trimMicroseconds(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let fraction = raw[raw.index(after: dot)...]
        let digits = fraction.prefix { $0.isNumber }
        guard digits.count > 3 else { return nil }
        let rest = fraction.dropFirst(digits.count)
        let zone: String = rest.isEmpty ? "Z" : String(rest)
        let head = String(raw[..<dot])
        let millis = String(digits.prefix(3))
        return "\(head).\(millis)\(zone)"
    }
}
