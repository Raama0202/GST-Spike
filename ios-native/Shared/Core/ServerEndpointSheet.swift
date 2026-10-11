import SwiftUI

/// Runtime API endpoint editor (same behaviour as the Flutter
/// `server_endpoint_dialog`). Only reachable when `ALLOW_SERVER_OVERRIDE=YES`.
struct ServerEndpointSheet: View {
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var input = ServerConfig.baseURL
    @State private var error: String?
    @State private var checking = false
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassTextField(
                            title: "API base URL",
                            text: $input,
                            systemImage: "server.rack",
                            prompt: "https://api.example.com/v1",
                            keyboard: .URL,
                            capitalization: .never
                        )
                        Text("Paste a host, host:port or full URL. A bare host uses /v1.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        DetailRow(label: "Compiled default", value: ServerConfig.compiledBaseURL)
                        if let error { ErrorBanner(message: error) }
                        if let healthMessage { InfoBanner(message: healthMessage, systemImage: "checkmark.seal.fill", color: Brand.success) }
                    }
                    .glassCard()

                    Button {
                        Task { await testConnection() }
                    } label: {
                        LoadingLabel(title: "Test connection", systemImage: "bolt.horizontal.circle", isLoading: checking)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glassSecondary)
                    .disabled(checking)

                    Button("Save endpoint") {
                        guard ServerConfig.save(input) != nil else {
                            error = "That URL is not valid."
                            return
                        }
                        onChange()
                        dismiss()
                    }
                    .buttonStyle(.glassPrimary)

                    if ServerConfig.isOverridden {
                        Button("Reset to default", role: .destructive) {
                            ServerConfig.reset()
                            onChange()
                            dismiss()
                        }
                        .buttonStyle(.glassSecondary(tint: Brand.danger))
                    }
                }
                .padding(GlassMetrics.screenPadding)
            }
            .glassScreen()
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func testConnection() async {
        error = nil
        healthMessage = nil
        guard let normalized = ServerConfig.normalize(input),
              var components = URLComponents(string: normalized)
        else {
            error = "That URL is not valid."
            return
        }
        components.path = "/health"
        guard let url = components.url else { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: url, timeoutInterval: 90)
            request.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                healthMessage = "Server is reachable."
            } else {
                error = "Server responded but /health did not return 200."
            }
        } catch {
            self.error = APIError.from(error).message
        }
    }
}
