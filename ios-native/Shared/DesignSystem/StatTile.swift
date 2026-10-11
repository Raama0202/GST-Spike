import SwiftUI

/// Glass metric tile used on both home screens and dashboards.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var color: Color = Brand.primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconBadge(systemImage: systemImage, color: color, size: 36)
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.display(30, weight: .heavy))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }
}

/// Gradient initials avatar.
struct AvatarView: View {
    let name: String
    var size: CGFloat = 48
    @Environment(\.brandColor) private var brand

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [brand, Brand.violet, Brand.pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
            .shadow(color: brand.opacity(0.35), radius: 10, x: 0, y: 6)
    }

    private var initials: String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." }).prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Brand mark shown on splash and login screens.
struct AppLogo: View {
    var systemImage = "doc.text.viewfinder"
    var size: CGFloat = 84
    @Environment(\.brandColor) private var brand

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [brand, Brand.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        .shadow(color: brand.opacity(0.5), radius: 24, x: 0, y: 14)
    }
}
