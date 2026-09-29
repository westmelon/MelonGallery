@preconcurrency import AppKit
import ImageIO

enum RW2Decoder {
  static func decode(at url: URL) async -> DecodedImage? {
    await IsolatedRAWDecoder.decode(at: url)
  }

  static func embeddedPreview(at url: URL) -> DecodedImage? {
    guard let source = imageSource(at: url) else { return nil }
    return embeddedPreview(from: source, maxPixelSize: 4096)
  }

  private static func imageSource(at url: URL) -> CGImageSource? {
    guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(
      url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
    ), CGImageSourceGetType(source) as String? == "com.panasonic.rw2-raw-image" else { return nil }
    return source
  }

  private static func embeddedPreview(from source: CGImageSource, maxPixelSize: Int) -> DecodedImage? {
    guard !Task.isCancelled,
          let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
          ] as CFDictionary) else { return nil }
    return decoded(preview, source: .embeddedPreview)
  }

  private static func decoded(_ image: CGImage, source: ImageDecodingSource) -> DecodedImage {
    DecodedImage(
      image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
      source: source
    )
  }
}
