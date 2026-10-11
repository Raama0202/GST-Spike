import SwiftUI

struct Employee: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var mobile: String
    var employeeCode: String
    var companyId: String
    var companyName: String?
    var branchId: String?
    var branchName: String?

    init(id: String, name: String, mobile: String, employeeCode: String, companyId: String, companyName: String?, branchId: String?, branchName: String?) {
        self.id = id
        self.name = name
        self.mobile = mobile
        self.employeeCode = employeeCode
        self.companyId = companyId
        self.companyName = companyName
        self.branchId = branchId
        self.branchName = branchName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id"), let companyId = c.string("companyId", "company_id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Employee missing id/companyId"))
        }
        self.id = id
        self.companyId = companyId
        name = c.string("name") ?? "Employee"
        mobile = c.string("mobile") ?? ""
        employeeCode = c.string("employeeCode", "employee_code") ?? ""
        companyName = c.string("companyName", "company_name")
        branchId = c.string("branchId", "branch_id")
        branchName = c.string("branchName", "branch_name")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(mobile, forKey: "mobile")
        try c.encode(employeeCode, forKey: "employeeCode")
        try c.encode(companyId, forKey: "companyId")
        try c.encodeIfPresent(companyName, forKey: "companyName")
        try c.encodeIfPresent(branchId, forKey: "branchId")
        try c.encodeIfPresent(branchName, forKey: "branchName")
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct AuthTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let access = c.string("accessToken", "access_token", "token") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing access token"))
        }
        accessToken = access
        refreshToken = c.string("refreshToken", "refresh_token") ?? ""
        expiresIn = c.int("expiresIn")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(accessToken, forKey: "accessToken")
        try c.encode(refreshToken, forKey: "refreshToken")
        try c.encodeIfPresent(expiresIn, forKey: "expiresIn")
    }
}

struct OTPVerifyResponse: Decodable {
    let tokens: AuthTokens
    let employee: Employee

    init(from decoder: Decoder) throws {
        tokens = try AuthTokens(from: decoder)
        let c = try decoder.container(keyedBy: AnyKey.self)
        if let employee = try? c.decode(Employee.self, forKey: "employee") {
            self.employee = employee
        } else if let profile = try? c.decode(Employee.self, forKey: "profile") {
            employee = profile
        } else {
            employee = try Employee(from: decoder)
        }
    }
}

struct ExpenseCategory: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var parentId: String?
    var sortOrder: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id") ?? UUID().uuidString
        name = c.string("name") ?? ""
        parentId = c.string("parentId")
        sortOrder = c.int("sortOrder") ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encodeIfPresent(parentId, forKey: "parentId")
        try c.encode(sortOrder, forKey: "sortOrder")
    }
}

struct Branch: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var code: String?
}

/// Tenant configuration downloaded after login and on every sync
/// (`GET /company/config`). Categories and branches never require an update.
struct CompanyConfig: Codable, Sendable {
    var companyId: String
    var companyName: String
    var industry: String
    var logoUrl: String?
    var primaryColorHex: String?
    var requiresGps: Bool
    var duplicateCheckEnabled: Bool
    var minOcrConfidenceWarn: Double
    var features: [String: Bool]
    var categories: [ExpenseCategory]
    var branches: [Branch]
    var updatedAt: Date?

    var brandColor: Color? { Color(hexString: primaryColorHex) }
    var galleryImportEnabled: Bool { features["galleryImport"] ?? true }
    var remarksRequired: Bool { features["remarksRequired"] ?? false }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        companyId = c.string("companyId") ?? ""
        companyName = c.string("companyName") ?? ""
        industry = c.string("industry") ?? ""
        logoUrl = c.string("logoUrl")
        primaryColorHex = c.string("primaryColorHex", "themeColor")
        requiresGps = c.bool("requiresGps") ?? false
        duplicateCheckEnabled = c.bool("duplicateCheckEnabled") ?? true
        minOcrConfidenceWarn = c.double("minOcrConfidenceWarn") ?? 0.55
        let rawFeatures = c.json("features")?.objectValue ?? [:]
        features = rawFeatures.reduce(into: [:]) { result, entry in result[entry.key] = entry.value.boolValue ?? false }
        categories = ((try? c.decode([FailableDecodable<ExpenseCategory>].self, forKey: "categories")) ?? [])
            .compactMap(\.value)
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        branches = ((try? c.decode([FailableDecodable<Branch>].self, forKey: "branches")) ?? []).compactMap(\.value)
        updatedAt = c.date("updatedAt")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(companyId, forKey: "companyId")
        try c.encode(companyName, forKey: "companyName")
        try c.encode(industry, forKey: "industry")
        try c.encodeIfPresent(logoUrl, forKey: "logoUrl")
        try c.encodeIfPresent(primaryColorHex, forKey: "primaryColorHex")
        try c.encode(requiresGps, forKey: "requiresGps")
        try c.encode(duplicateCheckEnabled, forKey: "duplicateCheckEnabled")
        try c.encode(minOcrConfidenceWarn, forKey: "minOcrConfidenceWarn")
        try c.encode(features, forKey: "features")
        try c.encode(categories, forKey: "categories")
        try c.encode(branches, forKey: "branches")
        try c.encodeIfPresent(updatedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: "updatedAt")
    }
}
