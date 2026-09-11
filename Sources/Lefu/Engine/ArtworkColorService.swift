import AppKit
import CoreImage
import LefuCore

/// 从封面提取主色并钳制为强调色。异步 + 按图像内容签名缓存，绝不占用主线程。
final class ArtworkColorService {
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    private var cache: [String: NSColor] = [:]
    private var misses = Set<String>()

    /// 以图像内容签名为键缓存（同签名 == 同图）。正负缓存都按签名，
    /// 因此同一首歌晚到的新封面不会被先前 null/灰阶的负缓存永久压制。
    /// 提取始终在后台队列，完成后回主线程写缓存并交付。
    func accent(forImage image: NSImage, signature: String, completion: @escaping (NSColor?) -> Void) {
        if let cached = cache[signature] { completion(cached); return }
        if misses.contains(signature) { completion(nil); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let color = self.extract(image)
            DispatchQueue.main.async {
                if let color { self.cache[signature] = color } else { self.misses.insert(signature) }
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
