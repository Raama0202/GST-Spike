import SwiftUI

// MARK: - Glass surface

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = GlassMetrics.cornerRadius
    var padding: CGFloat = 18
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(scheme == .dark ? 0.18 : 0.12))
                    }
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.08 : 0.35), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.35 : 0.85),
                            Color.white.opacity(scheme == .dark ? 0.05 : 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 24, x: 0, y: 12)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = GlassMetrics.cornerRadius, padding: CGFloat = 18, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, padding: padding, tint: tint))
    }
}

// MARK: - Buttons

struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.brandColor) private var brand
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [brand, Brand.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    )
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            }
            .shadow(color: brand.opacity(isEnabled ? 0.45 : 0), radius: 18, x: 0, y: 10)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(tint ?? Color.primary)
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPrimaryButtonStyle {
    static var glassPrimary: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle() }
    static var glassPrimaryCompact: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle(fullWidth: false) }
}

extension ButtonStyle where Self == GlassSecondaryButtonStyle {
    static var glassSecondary: GlassSecondaryButtonStyle { GlassSecondaryButtonStyle() }
    static var glassSecondaryCompact: GlassSecondaryButtonStyle { GlassSecondaryButtonStyle(fullWidth: false) }
    static func glassSecondary(tint: Color, fullWidth: Bool = true) -> GlassSecondaryButtonStyle {
        GlassSecondaryButtonStyle(fullWidth: fullWidth, tint: tint)
    }
}

/// Button label that swaps to a spinner while an async action runs.
struct LoadingLabel: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(.white)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}

/// Round frosted icon button used in headers.
struct GlassIconButton: View {
    let systemImage: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Brand.danger, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inputs

struct GlassTextField: View {
    let title: String
    @Binding var text: String
    var systemImage: String? = nil
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var isSecure = false
    var highlight = false
    var axis: Axis = .horizontal

    @FocusState private var focused: Bool
    @Environment(\.brandColor) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(focused ? brand : .secondary)
                        .frame(width: 20)
                }
                Group {
                    if isSecure {
                        SecureField(prompt, text: $text)
                    } else {
                        TextField(prompt, text: $text, axis: axis)
                            .lineLimit(axis == .vertical ? 2...5 : 1...1)
                    }
                }
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard != .default)
                .focused($focused)
                if highlight {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warning)
                        .help("Please verify this value")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous)
                    .fill(highlight ? Brand.warning.opacity(0.12) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous)
                    .strokeBorder(
                        focused ? brand.opacity(0.9) : (highlight ? Brand.warning.opacity(0.7) : Color.white.opacity(0.3)),
                        lineWidth: focused ? 1.5 : 1
                    )
            }
            .animation(.easeOut(duration: 0.2), value: focused)
        }
    }
}

struct GlassToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    @Binding var isOn: Bool
    @Environment(\.brandColor) private var brand

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                IconBadge(systemImage: systemImage, color: brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(brand)
    }
}

// MARK: - Small building blocks

struct IconBadge: View {
    let systemImage: String
    var color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            )
            .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(20, weight: .bold))
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 4)
    }
}

/// Selectable capsule used for filters and category suggestions.
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool
    let action: () -> Void
    @Environment(\.brandColor) private var brand

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(LinearGradient(colors: [brand, Brand.violet], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.4 : 0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

/// Label/value row used in detail screens.
struct DetailRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(height: 1)
    }
}
