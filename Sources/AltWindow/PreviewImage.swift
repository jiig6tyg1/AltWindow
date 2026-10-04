import AppKit

enum PreviewImage {
    static let longestEdge = 760 // Up to 380pt cards on a Retina screen; cache remains bounded.

    /// ScreenCaptureKit normally supplies the requested small bitmap already.
    /// Reuse it instead of decoding/copying every frame. Bound unexpected larger images.
    static func make(_ source: CGImage, longestEdge: Int = longestEdge) -> NSImage? {
        if max(source.width, source.height) <= longestEdge {
            return NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height))
        }
        let factor = min(1, Double(longestEdge) / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * factor))
        let height = max(1, Int(Double(source.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    static func cost(_ image: NSImage) -> Int {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}
