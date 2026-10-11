import SwiftUI

/// Login → OTP flow. Same rules as the Android client: mobile-only sign in,
/// six-digit OTP, 30 s resend timer, "remember me".
struct LoginFlowView: View {
    @State private var path: [OTPRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            LoginView { mobile, remember in
                path.append(OTPRoute(mobile: mobile, rememberLogin: remember))
            }
            .navigationDestination(for: OTPRoute.self) { route in
                OTPView(mobile: route.mobile, rememberLogin: route.rememberLogin)
            }
        }
    }
}

struct OTPRoute: Hashable {
    let mobile: String
    let rememberLogin: Bool
}

struct LoginView: View {
    var onOtpSent: (String, Bool) -> Void

    @Environment(SessionModel.self) private var session
    @State private var mobile = ""
    @State private var rememberLogin = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var showServer = false
    @State private var appear = false

    private var digits: String { mobile.filter(\.isNumber) }
    private var isValid: Bool { (10...15).contains(digits.count) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 16) {
                    AppLogo(size: 88)
                    VStack(spacing: 6) {
                        Text("Welcome back")
                            .font(.display(32, weight: .heavy))
                        Text("Sign in with the mobile number registered by your company.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)

                VStack(alignment: .leading, spacing: 18) {
                    GlassTextField(
                        title: "Mobile number",
                        text: $mobile,
                        systemImage: "phone.fill",
                        prompt: "98765 43210",
                        keyboard: .phonePad,
                        capitalization: .never
                    )
                    .onChange(of: mobile) { _, value in
                        let filtered = String(value.filter { $0.isNumber || $0 == "+" || $0 == " " }.prefix(16))
                        if filtered != value { mobile = filtered }
                    }

                    Toggle(isOn: $rememberLogin) {
                        Label("Keep me signed in", systemImage: "lock.shield")
                            .font(.subheadline.weight(.medium))
                    }

                    if let error {
                        ErrorBanner(message: error)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Button {
                        Task { await sendOtp() }
                    } label: {
                        LoadingLabel(title: "Send OTP", systemImage: "arrow.right.circle.fill", isLoading: isLoading)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(!isValid || isLoading)
                }
                .glassCard(padding: 22)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 24)

                VStack(spacing: 6) {
                    Label("Secured with one-time passwords", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    if ServerConfig.canOverride {
                        Button {
                            showServer = true
                        } label: {
                            Label(ServerConfig.displayHost, systemImage: "server.rack")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, GlassMetrics.screenPadding)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .glassScreen()
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.25), value: error)
        .sheet(isPresented: $showServer) { ServerEndpointSheet() }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.05)) { appear = true }
        }
    }

    private func sendOtp() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        let normalized = mobile.hasPrefix("+") ? "+" + digits : digits
        do {
            try await session.requestOtp(mobile: normalized)
            onOtpSent(normalized, rememberLogin)
        } catch {
            self.error = APIError.from(error).message
        }
    }
}
