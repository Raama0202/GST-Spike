import PhotosUI
import SwiftUI

/// Output of capture + OCR handed to the review form.
struct ScanDraft: Identifiable, Hashable {
    let id: String
    let preview: UIImage
    let original: Data
    let compressed: Data
    let thumbnail: Data
    let isBlurry: Bool
    let extraction: ExtractionResult
    let extractionError: String?

    static func == (lhs: ScanDraft, rhs: ScanDraft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EmployeeContainer.self) private var container
    @Environment(CompanyConfigModel.self) private var config

    @State private var path: [ScanDraft] = []
    @State private var showDocumentScanner = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var step = 0
    @State private var error: String?
    @State private var didAutoLaunch = false

    private let steps = [
        ("wand.and.stars", "Enhancing image"),
        ("text.viewfinder", "Reading invoice text"),
        ("list.bullet.rectangle.portrait", "Extracting GST fields"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isProcessing { processingView } else { captureView }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isProcessing)
            .glassScreen()
            .navigationTitle("Scan invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isProcessing)
                }
            }
            .navigationDestination(for: ScanDraft.self) { draft in
                ReviewView(draft: draft, onRetake: {
                    path.removeAll()
                    launchCapture()
                }, onSubmitted: { dismiss() })
            }
        }
        .brand(config.brandColor)
        .fullScreenCover(isPresented: $showDocumentScanner) {
            DocumentScannerView(
                onScan: { image in
                    showDocumentScanner = false
                    Task { await process(image) }
                },
                onCancel: { showDocumentScanner = false },
                onError: { failure in
                    showDocumentScanner = false
                    error = failure.localizedDescription
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(
                onImage: { image in
                    showCamera = false
                    Task { await process(image) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await process(image)
                } else {
                    error = "Could not load that photo."
                }
            }
        }
        .onAppear {
            guard !didAutoLaunch else { return }
            didAutoLaunch = true
            launchCapture()
        }
    }

    // MARK: - Capture

    private var captureView: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                            .foregroundStyle(.white.opacity(0.5))
                        VStack(spacing: 12) {
                            AppLogo(systemImage: "doc.viewfinder", size: 76)
                            Text("Place the bill on a flat surface")
                                .font(.headline)
                            Text("The scanner finds the edges and crops automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                    .frame(height: 280)

                    Button {
                        launchCapture()
                    } label: {
                        Label("Open scanner", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.glassPrimary)

                    if config.config?.galleryImportEnabled ?? true {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Import from Photos", systemImage: "photo.on.rectangle.angled")
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.glassSecondary)
                    }
                }
                .glassCard(padding: 20)

                if let error {
                    ErrorBanner(message: error)
                }

                VStack(alignment: .leading, spacing: 12) {
                    tip("sun.max.fill", "Good light, no harsh shadows")
                    tip("rectangle.dashed", "Keep all four corners in frame")
                    tip("hand.raised.fill", "Hold steady until it captures")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .padding(GlassMetrics.screenPadding)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Brand.warning)
                .frame(width: 22)
            Text(text).font(.subheadline)
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(step + 1) / CGFloat(steps.count))
                    .stroke(
                        AngularGradient(colors: [Brand.cyan, Brand.violet, Brand.pink, Brand.cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: step)
                Image(systemName: steps[min(step, steps.count - 1)].0)
                    .font(.system(size: 44, weight: .semibold))
                    .symbolEffect(.pulse)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Group {
                            if index < step {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
                            } else if index == step {
                                ProgressView()
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 24)
                        Text(item.1)
                            .font(.subheadline.weight(index == step ? .bold : .regular))
                            .foregroundStyle(index <= step ? .primary : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .padding(.horizontal, GlassMetrics.screenPadding)
            Spacer()
        }
    }

    // MARK: - Actions

    private func launchCapture() {
        error = nil
        if DocumentScannerView.isSupported {
            showDocumentScanner = true
        } else if CameraPickerView.isAvailable {
            showCamera = true
        }
    }

    private func process(_ image: UIImage) async {
        error = nil
        step = 0
        isProcessing = true
        defer { isProcessing = false }

        guard let output = await container.pipeline.process(image) else {
            error = "Could not process the image. Please try again."
            return
        }
        step = 1
        let extraction: ExtractionResult
        var extractionError: String? = nil
        do {
            extraction = try await container.extractor.extract(image: output.enhanced, jpeg: output.compressed)
        } catch {
            extraction = ExtractionResult(fields: InvoiceFields(), confidence: 0, rawText: "", source: .onDevice)
            extractionError = "We couldn't read this bill automatically. Please enter the details."
        }
        step = 2
        try? await Task.sleep(for: .milliseconds(350))

        let draft = ScanDraft(
            id: UUID().uuidString.lowercased(),
            preview: output.enhanced,
            original: output.original,
            compressed: output.compressed,
            thumbnail: output.thumbnail,
            isBlurry: output.isLikelyBlurry,
            extraction: extraction,
            extractionError: extractionError
        )
        path.append(draft)
    }
}
