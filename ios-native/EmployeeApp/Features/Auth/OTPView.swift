import SwiftUI

struct OTPView: View {
    let mobile: String
    let rememberLogin: Bool

    @Environment(SessionModel.self) private var session
    @Environment(\.brandColor) private var brand
    @State private var code = ""
    @State private var isVerifying = false
    @State private var error: String?
    @State private var secondsLeft = EmployeeConstants.otpResendSeconds
    @State private var shake = false
    @FocusState private var focused: Bool

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    IconBadge(systemImage: "message.badge.filled.fill", color: brand, size: 64)
                    Text("Verify your number")
                        .font(.display(28, weight: .heavy))
                    Text("Enter the 6-digit code sent to **\(mobile)**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 22) {
                    otpBoxes
                        .modifier(ShakeEffect(animatableData: shake ? 1 : 0))

                    if let error {
                        ErrorBanner(message: error)
                    }

                    Button {
                        Task { await verify() }
                    } label: {
                        LoadingLabel(title: "Verify & continue", systemImage: "checkmark.circle.fill", isLoading: isVerifying)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(code.count != EmployeeConstants.otpLength || isVerifying)

                    Button {
                        Task { await resend() }
                    } label: {
                        Text(secondsLeft > 0 ? "Resend code in \(secondsLeft)s" : "Resend code")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .disabled(secondsLeft > 0)
                }
                .glassCard(padding: 22)
            }
            .padding(.horizontal, GlassMetrics.screenPadding)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .glassScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onReceive(timer) { _ in if secondsLeft > 0 { secondsLeft -= 1 } }
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(EmployeeConstants.otpLength))
            if digits != value { code = digits }
            if digits.count == EmployeeConstants.otpLength, !isVerifying {
                Task { await verify() }
            }
        }
    }

    private var otpBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.02)

            HStack(spacing: 10) {
                ForEach(0..<EmployeeConstants.otpLength, id: \.self) { index in
                    let character = index < code.count ? String(Array(code)[index]) : ""
                    let isActive = focused && index == min(code.count, EmployeeConstants.otpLength - 1)
                    Text(character)
                        .font(.display(26, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isActive ? brand : Color.white.opacity(0.3), lineWidth: isActive ? 2 : 1)
                        )
                        .scaleEffect(character.isEmpty ? 1 : 1.04)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: character)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
    }

    private func verify() async {
        guard code.count == EmployeeConstants.otpLength, !isVerifying else { return }
        error = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await session.verifyOtp(mobile: mobile, otp: code, rememberLogin: rememberLogin)
        } catch {
            self.error = APIError.from(error).message
            code = ""
            withAnimation(.default) { shake.toggle() }
        }
    }

    private func resend() async {
        error = nil
        do {
            try await session.requestOtp(mobile: mobile)
            secondsLeft = EmployeeConstants.otpResendSeconds
        } catch {
            self.error = APIError.from(error).message
        }
    }
}

/// Horizontal shake for a wrong code.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 6), y: 0))
    }
}
