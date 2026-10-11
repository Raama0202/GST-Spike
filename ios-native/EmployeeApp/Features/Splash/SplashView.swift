import SwiftUI

struct SplashView: View {
    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 150, height: 150)
                    .scaleEffect(pulse ? 1.25 : 0.9)
                    .opacity(pulse ? 0 : 0.8)
                AppLogo(size: 96)
                    .scaleEffect(appear ? 1 : 0.6)
            }
            VStack(spacing: 6) {
                Text("GST Expense Scanner")
                    .font(.display(28, weight: .heavy))
                Text("Scan • Extract • Sync")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            ProgressView()
                .padding(.top, 12)
                .opacity(appear ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appear = true }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
