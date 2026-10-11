import SwiftUI
import Observation

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.brandColor) private var brand

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(brand.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [brand, Brand.violet], startPoint: .top, endPoint: .bottom))
            }
            Text(title)
                .font(.display(19, weight: .semibold))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassPrimaryCompact)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassCard()
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(Brand.danger)
                .font(.title3)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.danger)
            }
        }
        .glassCard(cornerRadius: 18, padding: 14, tint: Brand.danger)
    }
}

struct InfoBanner: View {
    let message: String
    var systemImage = "info.circle.fill"
    var color: Color = Brand.warning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.title3)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(cornerRadius: 18, padding: 14, tint: color)
    }
}

/// Frosted HUD shown over a screen while a blocking operation runs.
struct LoadingOverlay: View {
    let isVisible: Bool
    var message: String = "Please wait…"

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(28)
                .glassCard()
            }
            .transition(.opacity)
        }
    }
}

/// Skeleton row used while lists load.
struct ShimmerRow: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(height: 76)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: phase * proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.5 }
            }
    }
}

// MARK: - Toasts

@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        enum Kind { case success, error, info }
        let id = UUID()
        let message: String
        let kind: Kind
    }

    private(set) var current: Toast? = nil
    @ObservationIgnored private var dismissTask: Task<Void, Never>? = nil

    func show(_ message: String, kind: Toast.Kind = .info) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            current = Toast(message: message, kind: kind)
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.current = nil }
        }
    }

    func success(_ message: String) { show(message, kind: .success) }
    func error(_ message: String) { show(message, kind: .error) }
}

private struct ToastHost: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: icon(toast.kind))
                        .foregroundStyle(color(toast.kind))
                    Text(toast.message)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(color(toast.kind).opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 8)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .sensoryFeedback(trigger: center.current) { _, new in
            switch new?.kind {
            case .success: return .success
            case .error: return .error
            default: return nil
            }
        }
    }

    private func icon(_ kind: ToastCenter.Toast.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ kind: ToastCenter.Toast.Kind) -> Color {
        switch kind {
        case .success: return Brand.success
        case .error: return Brand.danger
        case .info: return Brand.primary
        }
    }
}

extension View {
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHost(center: center))
    }
}
