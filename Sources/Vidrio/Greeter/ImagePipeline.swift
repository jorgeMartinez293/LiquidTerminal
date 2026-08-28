import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decodes a sprite and re-encodes it for terminal display, replacing
/// ImageMagick's `magick "$file" -sample 500%`. The 5x nearest-neighbor
/// upscale exists only to defeat smoothing further down the pipeline (here:
/// SwiftTerm's `image.draw(in:)`, which uses default/smooth interpolation) —
/// scaling once with `.none` here keeps pixel art crisp without touching
/// SwiftTerm's shared kitty/iTerm image renderer, which other apps also use.
enum ImagePipeline {
    struct RenderedSprite {
        /// Encoded file bytes ready for the OSC 1337 payload — PNG for a
        /// single still frame, animated GIF when the source has more than one.
        let data: Data
        /// Native pixel size of the *source* frame (before upscaling), used
        /// to compute the sprite's terminal-cell footprint.
        let nativeSize: CGSize
        let isAnimated: Bool
    }

    private static let upscale = 5

    static func render(fileAt url: URL, staticFrameOnly: Bool) -> RenderedSprite? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frameCount = staticFrameOnly ? min(1, CGImageSourceGetCount(source)) : CGImageSourceGetCount(source)
        guard frameCount > 0, let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let nativeSize = CGSize(width: firstFrame.width, height: firstFrame.height)

        if frameCount <= 1 {
            guard let scaled = nearestNeighborScaled(firstFrame),
                  let png = encodePNG(scaled)
            else { return nil }
            return RenderedSprite(data: png, nativeSize: nativeSize, isAnimated: false)
        }

        var frames: [(image: CGImage, delay: Double)] = []
        for i in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, i, nil),
                  let scaled = nearestNeighborScaled(frame)
            else { continue }
            frames.append((scaled, frameDelay(source, index: i)))
        }
        guard !frames.isEmpty, let gif = encodeAnimatedGIF(frames) else { return nil }
        return RenderedSprite(data: gif, nativeSize: nativeSize, isAnimated: true)
    }

    private static func nearestNeighborScaled(_ image: CGImage) -> CGImage? {
        let width = image.width * upscale
        let height = image.height * upscale
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func frameDelay(_ source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        return unclamped ?? clamped ?? 0.1
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func encodeAnimatedGIF(_ frames: [(image: CGImage, delay: Double)]) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frame.delay] as CFDictionary
            ]
            CGImageDestinationAddImage(dest, frame.image, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
