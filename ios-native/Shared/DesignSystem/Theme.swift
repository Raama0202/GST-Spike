import SwiftUI

/// Palette shared by the employee and admin apps. The tenant's
/// `primaryColorHex` from `/company/config` overrides `Brand.primary` at runtime.
enum Brand {
    static let primary = Color(hex: "0B5FFF")
    static let indigo = Color(hex: "4F46E5")
    static let violet = Color(hex: "7C3AED")
    static let cyan = Color(hex: "06B6D4")
    static let teal = Color(hex: "14B8A6")
    static let pink = Color(hex: "EC4899")
    static let success = Color(hex: "10B981")
    static let warning = Color(hex: "F59E0B")
    static let danger = Color(hex: "EF4444")
    static let orange = Color(hex: "F97316")

    static let defaultHex = "0B5FFF"
}

extension Color {
    init(hex: String) {
        self = Color(hexString: hex) ?? Brand.primary
    }

    init?(hexString: String?) {
        guard var text = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt64(text, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Six-digit uppercase hex, used when the admin picks a theme colour.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

private struct BrandColorKey: EnvironmentKey {
    static let defaultValue: Color = Brand.primary
}

extension EnvironmentValues {
    var brandColor: Color {
        get { self[BrandColorKey.self] }
        set { self[BrandColorKey.self] = newValue }
    }
}

extension View {
    /// Applies the tenant colour to the environment and the system tint.
    func brand(_ color: Color) -> some View {
        environment(\.brandColor, color).tint(color)
    }
}

enum GlassMetrics {
    static let cornerRadius: CGFloat = 24
    static let smallRadius: CGFloat = 16
    static let screenPadding: CGFloat = 20
    static let tabBarClearance: CGFloat = 96
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
