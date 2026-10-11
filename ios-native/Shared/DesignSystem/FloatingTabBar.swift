import SwiftUI

struct TabItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
    var badge: Int = 0
}

/// Floating frosted tab bar with an optional raised centre action
/// (the employee app uses it for "Scan").
struct FloatingTabBar<ID: Hashable>: View {
    let items: [TabItem<ID>]
    @Binding var selection: ID
    var centerAction: (systemImage: String, action: () -> Void)? = nil

    @Namespace private var indicator
    @Environment(\.brandColor) private var brand

    var body: some View {
        HStack(spacing: 0) {
            let split = items.count / 2
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if centerAction != nil && index == split {
                    centerButton
                }
                tabButton(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    private func tabButton(_ item: TabItem<ID>) -> some View {
        let selected = item.id == selection
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item.id }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 19, weight: selected ? .bold : .medium))
                    .symbolVariant(selected ? .fill : .none)
                    .overlay(alignment: .topTrailing) {
                        if item.badge > 0 {
                            Circle().fill(Brand.danger).frame(width: 9, height: 9).offset(x: 5, y: -3)
                        }
                    }
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? brand : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(brand.opacity(0.14))
                        .matchedGeometryEffect(id: "indicator", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    @ViewBuilder
    private var centerButton: some View {
        if let centerAction {
            Button(action: centerAction.action) {
                Image(systemName: centerAction.systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(
                        LinearGradient(colors: [brand, Brand.violet], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: brand.opacity(0.55), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .offset(y: -14)
            .accessibilityLabel("Scan invoice")
        }
    }
}
