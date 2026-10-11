import SwiftUI

struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var type: String
    var title: String
    var body: String
    var createdAt: Date?
    var read: Bool
    var invoiceServerId: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing id"))
        }
        self.id = id
        type = c.string("type") ?? "companyAnnouncement"
        title = c.string("title") ?? "Notification"
        body = c.string("body") ?? ""
        createdAt = c.date("createdAt")
        read = c.bool("read") ?? false
        invoiceServerId = c.string("invoiceServerId")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(type, forKey: "type")
        try c.encode(title, forKey: "title")
        try c.encode(body, forKey: "body")
        try c.encodeIfPresent(createdAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: "createdAt")
        try c.encode(read, forKey: "read")
        try c.encodeIfPresent(invoiceServerId, forKey: "invoiceServerId")
    }

    /// Icon and colour per notification `type` enum from the API contract.
    var style: (systemImage: String, color: Color) {
        switch type {
        case "billApproved": return ("checkmark.seal.fill", Brand.success)
        case "billRejected": return ("xmark.seal.fill", Brand.danger)
        case "billReturned": return ("arrow.uturn.backward.circle.fill", Brand.orange)
        case "appUpdate": return ("arrow.down.app.fill", Brand.violet)
        default: return ("megaphone.fill", Brand.primary)
        }
    }
}
