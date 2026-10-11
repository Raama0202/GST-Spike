import Foundation

enum Formatters {
    static let inr: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.currencySymbol = "₹"
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy, h:mm a"
        return f
    }()

    static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return inr.string(from: NSNumber(value: value)) ?? "₹\(value)"
    }

    /// Plain numeric text for editable amount fields.
    static func amountText(_ value: Double?) -> String {
        guard let value else { return "" }
        return decimal.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func parseAmount(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "₹", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    static func dayString(_ date: Date?) -> String {
        guard let date else { return "—" }
        return day.string(from: date)
    }

    static func relativeString(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    /// `2026-07` period key used by the ITC endpoints.
    static func periodKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 2026, parts.month ?? 1)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `vendorName` → `Vendor Name`
    var humanizedKey: String {
        var result = ""
        for character in self {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result.replacingOccurrences(of: "_", with: " ").capitalized
            .replacingOccurrences(of: "Gstin", with: "GSTIN")
            .replacingOccurrences(of: "Cgst", with: "CGST")
            .replacingOccurrences(of: "Sgst", with: "SGST")
            .replacingOccurrences(of: "Igst", with: "IGST")
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
