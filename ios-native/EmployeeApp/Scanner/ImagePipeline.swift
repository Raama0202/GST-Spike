import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Produces the three renditions the API stores (original / compressed ≤ 1 MB
/// / thumbnail) plus a blur score, mirroring the Android image pipeline.
struct ImagePipeline: Sendable {
    struct Output: Sendable {
        let enhanced: UIImage
        let original: Data
        let compressed: Data
        let thumbnail: Data
        let blurVariance: Double

        var isLikelyBlurry: Bool { blurVariance < EmployeeConstants.blurVarianceThreshold }
    }

    func process(_ input: UIImage) async -> Output? {
        await Task.detached(priority: .userInitiated) {
            let upright = Self.normalized(input, maxEdge: 3000)
            let enhanced = Self.enhance(upright) ?? upright
            guard let original = upright.jpegData(compressionQuality: 0.9),
                  let compressed = Self.compress(Self.normalized(enhanced, maxEdge: 2000), maxBytes: EmployeeConstants.maxUploadImageBytes),
                  let thumbnail = Self.normalized(enhanced, maxEdge: EmployeeConstants.thumbnailMaxEdge).jpegData(compressionQuality: 0.7)
            else { return nil }
            let blur = Self.laplacianVariance(enhanced)
            return Output(enhanced: enhanced, original: original, compressed: compressed, thumbnail: thumbnail, blurVariance: blur)
        }.value
    }

    /// Redraws upright (EXIF orientation applied) and caps the longest edge.
    private static func normalized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Mild contrast boost and shadow lift for paper receipts.
    private static func enhance(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var output = CIImage(cgImage: cg)

        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = output
        shadows.shadowAmount = 0.35
        shadows.highlightAmount = 1.0
        output = shadows.outputImage ?? output

        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.contrast = 1.12
        controls.saturation = 0.95
        controls.brightness = 0.02
        output = controls.outputImage ?? output

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = output
        sharpen.sharpness = 0.4
        output = sharpen.outputImage ?? output

        guard let rendered = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    /// Steps JPEG quality down until the file fits the upload budget.
    private static func compress(_ image: UIImage, maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.85
        var current = image
        while true {
            guard let data = current.jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes { return data }
            if quality > 0.45 {
                quality -= 0.1
            } else {
                let edge = max(current.size.width, current.size.height) * 0.8
                if edge < 640 { return data }
                current = normalized(current, maxEdge: edge)
                quality = 0.75
            }
        }
    }

    /// Variance of the Laplacian on a 512 px grayscale copy — the same blur
    /// heuristic as Android (low variance = few edges = likely blurry).
    private static func laplacianVariance(_ image: UIImage) -> Double {
        let small = normalized(image, maxEdge: 512)
        guard let cg = small.cgImage else { return 1000 }
        let width = cg.width, height = cg.height
        guard width > 2, height > 2 else { return 1000 }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 1000 }

        var sum = 0.0, sumSquares = 0.0
        var count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = -4 * Double(pixels[i])
                    + Double(pixels[i - 1]) + Double(pixels[i + 1])
                    + Double(pixels[i - width]) + Double(pixels[i + width])
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return 1000 }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }
}
