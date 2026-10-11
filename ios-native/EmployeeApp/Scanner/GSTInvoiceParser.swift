import Foundation

/// Heuristic parser for Indian GST invoice OCR text — a port of the Android
/// `GstInvoiceParser` with a few robustness fixes for Vision output (optional
/// label separators, Indian lakh digit grouping, dd.mm.yyyy dates).
struct GSTInvoiceParser {
    struct Result {
        let fields: InvoiceFields
        let confidence: Double
        let rawText: String
    }

    private static let gstin = regex(#"\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z])\b"#)
    private static let invoiceNumber = regex(#"(?:invoice\s*(?:no\.?|number|#)|bill\s*no\.?)\s*[:\-]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{0,31})"#)
    private static let shortInvoiceNumber = regex(#"(?:^|[^\w])inv\.?\s*(?:no\.?|#)?\s*[:\-]\s*([A-Za-z0-9][A-Za-z0-9\-\/]{0,31})"#)
    private static let dayFirstDate = regex(#"\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b"#)
    private static let yearFirstDate = regex(#"\b(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})\b"#)
    private static let amount = #"((?:[0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]+)(?:\.[0-9]{1,2})?)(?![0-9]*\s*%)"#

    func parse(lines: [String], averageConfidence: Double?) -> Result {
        let rawText = lines.joined(separator: "\n")
        let fields = parseFields(rawText: rawText, lines: lines)
        let ocrScore = averageConfidence ?? (rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 0.5)
        let confidence = rawText.isEmpty ? 0 : min(max(ocrScore * 0.45 + Self.fieldScore(fields) * 0.55, 0), 1)
        return Result(fields: fields, confidence: confidence, rawText: rawText)
    }

    func parseFields(rawText: String, lines: [String]) -> InvoiceFields {
        let text = rawText.replacingOccurrences(of: "\r", with: "\n")
        let gstin = extractGstin(text)
        return InvoiceFields(
            vendorName: extractVendorName(lines, gstin: gstin),
            gstin: gstin,
            invoiceNumber: extractInvoiceNumber(text, lines: lines),
            invoiceDate: extractDate(text),
            taxableValue: labeledAmount(text, ["TAXABLE VALUE", "TAXABLE AMOUNT", "TAXABLE", "ASSESSABLE"]),
            cgst: labeledAmount(text, ["CGST"]),
            sgst: labeledAmount(text, ["SGST"]),
            igst: labeledAmount(text, ["IGST"]),
            discount: labeledAmount(text, ["LESS DISCOUNT", "DISCOUNT"]),
            netAmount: extractNetAmount(text)
        )
    }

    static func fieldScore(_ fields: InvoiceFields) -> Double {
        var score = 0.0
        if fields.gstin != nil { score += 0.2 }
        if fields.invoiceNumber != nil { score += 0.15 }
        if fields.invoiceDate != nil { score += 0.15 }
        if fields.netAmount != nil { score += 0.2 }
        if fields.taxableValue != nil { score += 0.1 }
        if fields.cgst != nil || fields.sgst != nil || fields.igst != nil { score += 0.1 }
        if fields.vendorName != nil { score += 0.1 }
        return score
    }

    // MARK: - Extractors

    private func extractGstin(_ text: String) -> String? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return Self.firstGroup(Self.gstin, in: compact)?.uppercased()
    }

    private func extractInvoiceNumber(_ text: String, lines: [String]) -> String? {
        if let value = Self.firstGroup(Self.invoiceNumber, in: text) ?? Self.firstGroup(Self.shortInvoiceNumber, in: text) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !["date", "dated", "dt"].contains(trimmed.lowercased()) { return trimmed }
        }
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("invoice") || lower.contains("inv no") else { continue }
            let parts = line.split(whereSeparator: { $0 == ":" || $0 == "#" })
            guard parts.count > 1 else { continue }
            let candidate = parts.last!.trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty, candidate.count <= 32, !candidate.lowercased().hasPrefix("invoice") {
                return candidate
            }
        }
        return nil
    }

    private func extractDate(_ text: String) -> Date? {
        let range = NSRange(text.startIndex..., in: text)
        for match in Self.dayFirstDate.matches(in: text, range: range) {
            if let d = Int(Self.group(match, 1, in: text) ?? ""),
               let m = Int(Self.group(match, 2, in: text) ?? ""),
               let y = Int(Self.group(match, 3, in: text) ?? ""),
               let date = Self.safeDate(year: y, month: m, day: d) {
                return date
            }
        }
        for match in Self.yearFirstDate.matches(in: text, range: range) {
            if let y = Int(Self.group(match, 1, in: text) ?? ""),
               let m = Int(Self.group(match, 2, in: text) ?? ""),
               let d = Int(Self.group(match, 3, in: text) ?? ""),
               let date = Self.safeDate(year: y, month: m, day: d) {
                return date
            }
        }
        return nil
    }

    private func labeledAmount(_ text: String, _ labels: [String]) -> Double? {
        for label in labels.sorted(by: { $0.count > $1.count }) {
            let pattern = NSRegularExpression.escapedPattern(for: label)
                + #"(?:\s*@\s*[0-9]+(?:\.[0-9]+)?\s*%?)?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*"#
                + Self.amount
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let raw = Self.firstGroup(regex, in: text)
            else { continue }
            if let value = Double(raw.replacingOccurrences(of: ",", with: "")) { return value }
        }
        return nil
    }

    /// Takes the largest of the "total"-style labels, like the Android parser.
    private func extractNetAmount(_ text: String) -> Double? {
        let labels = ["GRAND TOTAL", "NET AMOUNT", "TOTAL AMOUNT", "AMOUNT PAYABLE", "NET PAYABLE", "INVOICE TOTAL", "TOTAL"]
        return labels.compactMap { labeledAmount(text, [$0]) }.max()
    }

    private func extractVendorName(_ lines: [String], gstin: String?) -> String? {
        for line in lines.prefix(8) {
            let lower = line.lowercased()
            let isHeading = lower.contains("tax invoice")
                || (lower.contains("invoice") && lower.count < 14)
                || lower.hasPrefix("gstin")
                || lower.hasPrefix("date")
                || lower.hasPrefix("original")
                || lower.hasPrefix("duplicate")
            if isHeading { continue }
            if line.count >= 3, line.count <= 80, line.rangeOfCharacter(from: .letters) != nil { return line }
        }
        if let gstin {
            let allowed = Self.regex(#"^[A-Za-z0-9 &.,\-]+$"#)
            for line in lines where !line.uppercased().contains(gstin) {
                let range = NSRange(line.startIndex..., in: line)
                if line.count >= 3, allowed.firstMatch(in: line, range: range) != nil { return line }
            }
        }
        return nil
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    }

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return group(match, 1, in: text)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func safeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }
}
