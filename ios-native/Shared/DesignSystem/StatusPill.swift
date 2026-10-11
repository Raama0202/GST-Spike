import SwiftUI

/// Colour-coded capsule for every status string the API returns
/// (approval, sync, company, ITC match and reminder states).
struct StatusPill: View {
    let status: String
    var compact = false

    var body: some View {
        let style = Self.style(for: status)
        HStack(spacing: 5) {
            Circle()
                .fill(style.color)
                .frame(width: 6, height: 6)
            Text(style.label)
                .lineLimit(1)
        }
        .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
        .foregroundStyle(style.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(style.color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(style.color.opacity(0.35), lineWidth: 1))
    }

    static func style(for raw: String) -> (label: String, color: Color) {
        let key = raw.lowercased()
        switch key {
        case "approved", "active", "matched", "resolved", "uploaded_ok", "ready", "sent_link":
            return (pretty(key), Brand.success)
        case "pending", "processing", "partial", "manual_followup":
            return (pretty(key), Brand.warning)
        case "uploading", "uploaded", "syncing":
            return (pretty(key), Brand.primary)
        case "rejected", "failed", "suspended", "expired", "cancelled", "mismatch":
            return (pretty(key), Brand.danger)
        case "returned", "missing_in_2b":
            return (key == "missing_in_2b" ? "Missing in 2B" : "Returned", Brand.orange)
        case "missing_in_books":
            return ("Missing in books", Brand.violet)
        case "inactive":
            return ("Inactive", Color.gray)
        default:
            return (pretty(key), Color.gray)
        }
    }

    private static func pretty(_ key: String) -> String {
        switch key {
        case "manual_followup": return "Follow-up"
        case "sent_link": return "Link sent"
        case "uploaded": return "Uploaded"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
