import UIKit
import Vision

/// On-device text recognition (Apple Vision) — replaces ML Kit's Latin
/// text recognizer and works fully offline.
struct VisionOCRService: Sendable {
    struct Output: Sendable {
        let lines: [String]
        let averageConfidence: Double?
    }

    func recognize(_ image: UIImage) async throws -> Output {
        guard let cgImage = image.cgImage else {
            throw APIError(kind: .unknown, status: nil, message: "Could not read the scanned image.")
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            // Vision's origin is bottom-left: read rows top-to-bottom, then left-to-right.
            let sorted = observations.sorted { a, b in
                let rowDelta = a.boundingBox.midY - b.boundingBox.midY
                if abs(rowDelta) > 0.012 { return rowDelta > 0 }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            var lines: [String] = []
            var scores: [Double] = []
            for observation in sorted {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                lines.append(text)
                scores.append(Double(candidate.confidence))
            }
            let average: Double? = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            return Output(lines: lines, averageConfidence: average)
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Hybrid extractor, same strategy as the Android `OcrService`: Gemini vision
/// on the server when available, otherwise on-device Vision + GST parser.
/// AI outages never block a scan.
struct InvoiceExtractor: Sendable {
    let api: APIClient
    let ocr = VisionOCRService()
    let parser = GSTInvoiceParser()

    func extract(image: UIImage, jpeg: Data) async throws -> ExtractionResult {
        if let ai = try? await extractWithAI(jpeg) {
            return ai
        }
        let output = try await ocr.recognize(image)
        guard !output.lines.isEmpty else {
            throw APIError(kind: .validation, status: nil, message: "No text detected on the invoice image.")
        }
        let parsed = parser.parse(lines: output.lines, averageConfidence: output.averageConfidence)
        return ExtractionResult(fields: parsed.fields, confidence: parsed.confidence, rawText: parsed.rawText, source: .onDevice)
    }

    private func extractWithAI(_ jpeg: Data) async throws -> ExtractionResult? {
        struct Status: Decodable { let available: Bool? }
        let status: Status = try await api.get(EmployeeEndpoints.extractStatus)
        guard status.available == true else { return nil }

        var form = MultipartForm()
        form.addFile("image", filename: "invoice.jpg", mimeType: "image/jpeg", data: jpeg)
        let data = try await api.raw(.post, EmployeeEndpoints.extract, body: form.finalized(), contentType: form.contentType, timeout: 90)
        let fields = try JSONDecoder().decode(InvoiceFields.self, from: data)
        let meta = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let confidence = (meta["confidence"] as? Double) ?? 0.7
        let provider = (meta["provider"] as? String) ?? "ai"
        let notes = meta["notes"] as? String
        let raw = ["Extracted by \(provider)", notes.map { "Notes: \($0)" }].compactMap { $0 }.joined(separator: "\n")
        return ExtractionResult(fields: fields, confidence: min(max(confidence, 0), 1), rawText: raw, source: .ai)
    }
}
