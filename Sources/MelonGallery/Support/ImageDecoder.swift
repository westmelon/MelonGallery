@preconcurrency import AppKit
import ImageIO

enum ImageDecoder {
  static func thumbnail(at url: URL, maxPixelSize: Int) -> NSImage? {
    let sourceOptions = [
      kCGImageSourceShouldCache: false
    ] as CFDictionary

    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
      return nil
    }

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    return NSImage(
      cgImage: cgImage,
      size: NSSize(width: cgImage.width, height: cgImage.height)
    )
  }

  static func displayImage(at url: URL, maxPixelSize: Int) -> NSImage? {
    thumbnail(at: url, maxPixelSize: maxPixelSize) ?? NSImage(contentsOf: url)
  }
}
