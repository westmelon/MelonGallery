@preconcurrency import AppKit
import ImageIO

enum ImageDecoder {
  private static let quickLookService = ThumbnailService()
  private static let rawPreviewCache = RAWPreviewCache()

  static func thumbnail(at url: URL, maxPixelSize: Int) -> NSImage? {
    let sourceOptions = [
      kCGImageSourceShouldCache: false
    ] as CFDictionary

    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
      return nil
    }

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: url.pathExtension.lowercased() != "rw2",
      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
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

  static func displayImage(at url: URL, maxPixelSize: Int) async -> NSImage? {
    await comparisonImage(at: url) ?? NSImage(contentsOf: url) ?? thumbnail(at: url, maxPixelSize: maxPixelSize)
  }

  static func comparisonImage(at url: URL) async -> NSImage? {
    if url.pathExtension.lowercased() == "rw2" {
      return await RW2Decoder.decode(at: url)?.image
    }
    if url.pathExtension.lowercased() == "pdf" {
      return NSImage(contentsOf: url)
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    // Decode an orientation-correct, full-resolution first frame with pixel-based dimensions.
    let image = thumbnail(at: url, maxPixelSize: max(width, height))
    image?.cacheMode = .never
    return image
  }

  static func preview(
    at url: URL,
    onPreview: (@MainActor @Sendable (DecodedImage) -> Void)? = nil,
    loadFullResolution: Bool = true,
    cachesFullResolution: Bool = true
  ) async -> DecodedImage? {
    guard !Task.isCancelled else { return nil }
    let isRAW = url.pathExtension.lowercased() == "rw2"
    let worker = Task.detached(priority: .userInitiated) {
      guard !Task.isCancelled else { return nil as DecodedImage? }
      if isRAW {
        let version = RAWPreviewCache.Version(url: url)
        if cachesFullResolution,
           let cached = rawPreviewCache.image(at: url, version: version) { return cached }
        let embedded = RW2Decoder.embeddedPreview(at: url)
        if let embedded, let onPreview, !Task.isCancelled {
          await onPreview(embedded)
        }
        if !loadFullResolution { return embedded }
        guard !Task.isCancelled else { return nil }
        let decoded = await RW2Decoder.decode(at: url)
        if cachesFullResolution, let decoded, !Task.isCancelled {
          rawPreviewCache.insert(decoded, at: url, version: version)
        }
        return decoded
      }
      return await displayImage(at: url, maxPixelSize: 4096).map {
        DecodedImage(image: $0, source: .image)
      }
    }
    let result = await withTaskCancellationHandler {
      await worker.value
    } onCancel: {
      worker.cancel()
    }
    guard !Task.isCancelled else { return nil }
    if let result { return result }
    guard isRAW,
          let image = try? await quickLookService.quickLookThumbnail(for: url, pointSize: 2048, scale: 1),
          !Task.isCancelled,
          let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return DecodedImage(
      image: NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height)),
      source: .systemPreview
    )
  }
}
