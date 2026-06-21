@preconcurrency import AppKit
@preconcurrency import QuickLookThumbnailing
import Foundation

final class ThumbnailService: @unchecked Sendable {
  private let cache = NSCache<NSString, NSImage>()

  func thumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) async -> NSImage? {
    let pixelSize = max(Int(pointSize * scale), 64)
    let key = "\(url.path)-\(pixelSize)" as NSString

    if let cachedImage = cache.object(forKey: key) {
      return cachedImage
    }

    if Task.isCancelled {
      return nil
    }

    if let quickLookImage = try? await quickLookThumbnail(for: url, pointSize: pointSize, scale: scale) {
      cache.setObject(quickLookImage, forKey: key)
      return quickLookImage
    }

    if Task.isCancelled {
      return nil
    }

    if let imageIOThumbnail = ImageDecoder.thumbnail(at: url, maxPixelSize: pixelSize) {
      cache.setObject(imageIOThumbnail, forKey: key)
      return imageIOThumbnail
    }

    return nil
  }

  private func quickLookThumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) async throws -> NSImage {
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: CGSize(width: pointSize, height: pointSize),
      scale: scale,
      representationTypes: .thumbnail
    )
    let generator = QLThumbnailGenerator.shared

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        generator.generateBestRepresentation(for: request) { representation, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }

          guard let image = representation?.nsImage else {
            continuation.resume(throwing: ThumbnailError.noImage)
            return
          }

          continuation.resume(returning: image)
        }
      }
    } onCancel: {
      generator.cancel(request)
    }
  }
}

private enum ThumbnailError: Error {
  case noImage
}
