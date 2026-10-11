import SwiftUI

/// Tenant configuration read by every employee device via `/company/config`.
/// Changes reach Android and iOS on their next sync — no app update needed.
struct CompanySettingsView: View {
    @Environment(AdminSession.self) private var session
    @Environment(AdminWorkspace.self) private var workspace
    @Environment(ToastCenter.self) private var toasts

    @State private var loaded = false
    @State private var error: String?
    @State private var isSaving = false

    @State private var name = ""
    @State private var industry = ""
    @State private var logoUrl = ""
    @State private var color = Brand.primary
    @State private var requiresGps = false
    @State private var duplicateCheck = true
    @State private var minConfidence = 0.55
    @State private var features: [String: JSONValue] = [:]
    @State private var activationCode: String?

    private static let knownFeatures: [(key: String, title: String, subtitle: String, icon: String)] = [
        ("galleryImport", "Gallery import", "Allow picking invoices from photos", "photo.on.rectangle"),
        ("remarksRequired", "Require remarks", "Employees must add a note", "text.bubble"),
    ]

    var body: some View {
        ScrollView {
            if loaded {
                VStack(spacing: 18) {
                    preview
                    identityCard
                    captureCard
                    featuresCard
                    if let activationCode {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Activation code")
                            HStack {
                                Text(activationCode).font(.body.monospaced())
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = activationCode
                                    toasts.success("Copied")
                                } label: { Image(systemName: "doc.on.doc") }
                            }
                        }
                        .glassCard()
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        LoadingLabel(title: "Save settings", systemImage: "checkmark.circle.fill", isLoading: isSaving)
                    }
                    .buttonStyle(.glassPrimary)
                    .disabled(name.nilIfBlank == nil || isSaving)
                    .padding(.bottom, 24)
                }
                .padding(GlassMetrics.screenPadding)
            } else if let error {
                ErrorBanner(message: error) { Task { await load() } }
                    .padding(GlassMetrics.screenPadding)
            } else {
                ProgressView().padding(.top, 100)
            }
        }
        .glassScreen()
        .navigationTitle("Company settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
    }

    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 56, height: 56)
                if let url = ServerConfig.absoluteURL(logoUrl.nilIfBlank) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit().padding(8)
                    } placeholder: {
                        Image(systemName: "building.2.fill").foregroundStyle(.white)
                    }
                    .frame(width: 56, height: 56)
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name.nilIfBlank ?? "Company").font(.headline)
                Text("Employee app accent preview").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard(tint: color)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Identity")
            GlassTextField(title: "Company name", text: $name, systemImage: "building.2", capitalization: .words)
            GlassTextField(title: "Industry", text: $industry, systemImage: "briefcase", prompt: "Construction", capitalization: .words)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Industry.suggestions, id: \.self) { item in
                        GlassChip(title: item, isSelected: industry == item) { industry = item }
                    }
                }
            }
            GlassTextField(title: "Logo URL", text: $logoUrl, systemImage: "photo", prompt: "https://…", keyboard: .URL, capitalization: .never)
            ColorPicker(selection: $color, supportsOpacity: false) {
                Label("Brand colour  \(color.hexString)", systemImage: "paintpalette.fill")
                    .font(.subheadline)
            }
        }
        .glassCard()
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Capture rules")
            GlassToggleRow(title: "Require GPS", subtitle: "Attach location to every invoice", systemImage: "location.fill", isOn: $requiresGps)
            GlassToggleRow(title: "Duplicate check", subtitle: "Warn on repeated GSTIN + invoice number", systemImage: "doc.on.doc.fill", isOn: $duplicateCheck)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Low-confidence warning", systemImage: "gauge.with.dots.needle.50percent")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int((minConfidence * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                Slider(value: $minConfidence, in: 0.2...0.95, step: 0.05)
                Text("Employees see a review warning when OCR confidence is below this value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Features")
            ForEach(Self.knownFeatures, id: \.key) { feature in
                GlassToggleRow(title: feature.title, subtitle: feature.subtitle, systemImage: feature.icon, isOn: binding(for: feature.key, default: feature.key == "galleryImport"))
            }
            ForEach(otherBoolFeatures, id: \.self) { key in
                GlassToggleRow(title: key.humanizedKey, systemImage: "switch.2", isOn: binding(for: key, default: false))
            }
        }
        .glassCard()
    }

    private var otherBoolFeatures: [String] {
        let known = Set(Self.knownFeatures.map(\.key))
        return features.compactMap { key, value -> String? in
            guard !known.contains(key), case .bool = value else { return nil }
            return key
        }
        .sorted()
    }

    private func binding(for key: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { features[key]?.boolValue ?? defaultValue },
            set: { features[key] = .bool($0) }
        )
    }

    private func load() async {
        do {
            let settings = try await session.api.settings()
            apply(settings)
            loaded = true
            error = nil
        } catch {
            self.error = APIError.from(error).message
        }
    }

    private func apply(_ settings: CompanySettings) {
        name = settings.name
        industry = settings.industry
        logoUrl = settings.logoUrl ?? ""
        color = Color(hexString: settings.primaryColorHex) ?? Brand.primary
        requiresGps = settings.requiresGps
        duplicateCheck = settings.duplicateCheckEnabled
        minConfidence = settings.minOcrConfidenceWarn
        features = settings.features
        activationCode = settings.activationCode
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let input = CompanySettingsInput(
            name: name.trimmingCharacters(in: .whitespaces),
            industry: industry.trimmingCharacters(in: .whitespaces),
            logoUrl: logoUrl.nilIfBlank,
            primaryColorHex: color.hexString,
            requiresGps: requiresGps,
            duplicateCheckEnabled: duplicateCheck,
            minOcrConfidenceWarn: (minConfidence * 100).rounded() / 100,
            features: features
        )
        do {
            let saved = try await session.api.updateSettings(input)
            apply(saved)
            workspace.setCompanyName(saved.name)
            toasts.success("Settings saved — devices update on next sync")
        } catch {
            toasts.error(APIError.from(error).message)
        }
    }
}
