import SwiftUI

/// Vivid, slowly drifting colour field that every glass surface blurs.
struct GlassBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.brandColor) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: baseColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                orb(brand, diameter: w * 1.15)
                    .offset(x: drift ? -w * 0.30 : -w * 0.45, y: drift ? -h * 0.32 : -h * 0.22)

                orb(Brand.violet, diameter: w * 0.95)
                    .offset(x: drift ? w * 0.42 : w * 0.28, y: drift ? -h * 0.02 : h * 0.10)

                orb(Brand.cyan, diameter: w * 0.85)
                    .offset(x: drift ? -w * 0.18 : w * 0.05, y: drift ? h * 0.40 : h * 0.30)

                orb(Brand.pink, diameter: w * 0.55)
                    .offset(x: drift ? w * 0.30 : w * 0.45, y: drift ? h * 0.42 : h * 0.50)
                    .opacity(scheme == .dark ? 0.55 : 0.4)

                // Fine top sheen gives the field depth behind the glass.
                LinearGradient(
                    colors: [Color.white.opacity(scheme == .dark ? 0.04 : 0.25), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private var baseColors: [Color] {
        scheme == .dark
            ? [Color(hex: "070B1F"), Color(hex: "0E1236"), Color(hex: "120A2A")]
            : [Color(hex: "EEF2FF"), Color(hex: "F5F3FF"), Color(hex: "ECFEFF")]
    }

    private func orb(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(scheme == .dark ? 0.75 : 0.55), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 30)
    }
}

extension View {
    /// Places the animated glass backdrop behind a screen and clears system
    /// backgrounds so the colour field shows through lists and nav bars.
    func glassScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
