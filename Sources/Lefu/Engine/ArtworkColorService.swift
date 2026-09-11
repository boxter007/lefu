import AppKit
import CoreImage
import LefuCore

/// 从封面提取主色并钳制为强调色。异步 + 按 key 缓存，绝不占用主线程。
final class ArtworkColorService {
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    private var cache: [String: NSColor] = [:]
    private var misses = Set<String>()

    func accent(forKey key: String, image: NSImage, completion: @escaping (NSColor?) -> Void) {
        if let cached = cache[key] { completion(cached); return }
        if misses.contains(key) { completion(nil); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let color = self.extract(image)
            DispatchQueue.main.async {
                if let color { self.cache[key] = color } else { self.misses.insert(key) }
                completion(color)
            }
        }
    }

    private func extract(_ image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let rgb = RGB(r: Double(bitmap[0]) / 255, g: Double(bitmap[1]) / 255, b: Double(bitmap[2]) / 255)
        guard let clamped = AccentDerivation.clamp(rgb) else { return nil }
        return NSColor(srgbRed: clamped.r, green: clamped.g, blue: clamped.b, alpha: 1)
    }
}
