@preconcurrency import AppKit
@preconcurrency import QuickLookThumbnailing
import CryptoKit
import Foundation

final class ThumbnailService: @unchecked Sendable {
  private let cache = NSCache<NSString, NSImage>()
  private let cacheDirectory: URL?

  init() {
    cache.totalCostLimit = 64 * 1024 * 1024
    cacheDirectory = Self.makeCacheDirectory()
    if let cacheDirectory {
      Task.detached(priority: .utility) {
        Self.trimDiskCache(at: cacheDirectory)
      }
    }
  }

  func clearMemoryCache() {
    cache.removeAllObjects()
  }

  func thumbnail(
    for url: URL,
    modifiedAt: Date?,
    pointSize: CGFloat,
    scale: CGFloat
  ) async -> NSImage? {
    guard !Task.isCancelled else { return nil }
    let pixelSize = max(Int(pointSize * scale), 64)
    let modificationKey = modifiedAt?.timeIntervalSinceReferenceDate ?? 0
    let key = "\(url.path)-\(modificationKey)-\(pixelSize)" as NSString

    if let cachedImage = cache.object(forKey: key) {
      return cachedImage
    }

    let diskURL = cacheDirectory?.appendingPathComponent(Self.hashedFilename(for: key as String))
    if let diskURL {
      let diskImage = await Task.detached(priority: .utility) {
        ImageDecoder.thumbnail(at: diskURL, maxPixelSize: pixelSize)
      }.value
      guard !Task.isCancelled else { return nil }
      if let diskImage {
        cache.setObject(diskImage, forKey: key, cost: Self.estimatedCost(of: diskImage))
        return diskImage
      }
    }

    if Task.isCancelled {
      return nil
    }

    let imageIOThumbnail = await Task.detached(priority: .utility) {
      ImageDecoder.thumbnail(at: url, maxPixelSize: pixelSize)
    }.value
    guard !Task.isCancelled else { return nil }
    if let imageIOThumbnail {
      store(imageIOThumbnail, key: key, diskURL: diskURL)
      return imageIOThumbnail
    }

    if Task.isCancelled {
      return nil
    }

    if let quickLookImage = try? await quickLookThumbnail(for: url, pointSize: pointSize, scale: scale) {
      guard !Task.isCancelled else { return nil }
      store(quickLookImage, key: key, diskURL: diskURL)
      return quickLookImage
    }

    return nil
  }

  private func store(_ image: NSImage, key: NSString, diskURL: URL?) {
    cache.setObject(image, forKey: key, cost: Self.estimatedCost(of: image))
    guard let diskURL else {
      return
    }
    Task.detached(priority: .utility) {
      guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
      let bitmap = NSBitmapImageRep(cgImage: pixels)
      guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return
      }
      try? pngData.write(to: diskURL, options: .atomic)
    }
  }

  private static func makeCacheDirectory() -> URL? {
    guard let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      return nil
    }
    let directory = baseURL
      .appendingPathComponent("dev.neolin.MelonGallery", isDirectory: true)
      .appendingPathComponent("Thumbnails", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory
    } catch {
      return nil
    }
  }

  private static func hashedFilename(for key: String) -> String {
    let digest = SHA256.hash(data: Data(key.utf8))
    return digest.map { String(format: "%02x", $0) }.joined() + ".png"
  }

  private static func estimatedCost(of image: NSImage) -> Int {
    if let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      return pixels.bytesPerRow * pixels.height
    }
    let representation = image.representations.max {
      ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
    }
    guard let representation else {
      return 0
    }
    return representation.pixelsWide * representation.pixelsHigh * 4
  }

  private static func trimDiskCache(at directory: URL) {
    let maximumBytes: Int64 = 512 * 1024 * 1024
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    ) else {
      return
    }

    let entries = files.compactMap { url -> (URL, Date, Int64)? in
      guard let values = try? url.resourceValues(forKeys: keys) else {
        return nil
      }
      return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
    }
    var totalBytes = entries.reduce(Int64(0)) { $0 + $1.2 }

    for entry in entries.sorted(by: { $0.1 < $1.1 }) where totalBytes > maximumBytes {
      if (try? FileManager.default.removeItem(at: entry.0)) != nil {
        totalBytes -= entry.2
      }
    }
  }

  func quickLookThumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) async throws -> NSImage {
    try await withThrowingTaskGroup(of: NSImage.self) { group in
      group.addTask {
        try await self.generateQuickLookThumbnail(for: url, pointSize: pointSize, scale: scale)
      }
      group.addTask {
        try await Task.sleep(for: .seconds(5))
        throw ThumbnailError.timedOut
      }

      defer {
        group.cancelAll()
      }

      guard let image = try await group.next() else {
        throw ThumbnailError.noImage
      }
      return image
    }
  }

  private func generateQuickLookThumbnail(
    for url: URL,
    pointSize: CGFloat,
    scale: CGFloat
  ) async throws -> NSImage {
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: CGSize(width: pointSize, height: pointSize),
      scale: scale,
      representationTypes: .thumbnail
    )
    let generator = QLThumbnailGenerator.shared
    let requestState = ThumbnailRequestState()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        requestState.install(continuation)
        guard !Task.isCancelled else {
          requestState.finish(with: .failure(CancellationError()))
          return
        }

        generator.generateBestRepresentation(for: request) { representation, error in
          if let error {
            requestState.finish(with: .failure(error))
            return
          }

          guard let representation, representation.type == .thumbnail else {
            requestState.finish(with: .failure(ThumbnailError.noImage))
            return
          }

          requestState.finish(with: .success(representation.nsImage))
        }
      }
    } onCancel: {
      generator.cancel(request)
      requestState.finish(with: .failure(CancellationError()))
    }
  }
}

private enum ThumbnailError: Error {
  case noImage
  case timedOut
}

private final class ThumbnailRequestState: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<NSImage, Error>?
  private var pendingResult: Result<NSImage, Error>?
  private var isFinished = false

  func install(_ continuation: CheckedContinuation<NSImage, Error>) {
    lock.lock()
    if isFinished, let pendingResult {
      lock.unlock()
      continuation.resume(with: pendingResult)
      return
    }
    self.continuation = continuation
    lock.unlock()
  }

  func finish(with result: Result<NSImage, Error>) {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      return
    }

    isFinished = true
    guard let continuation else {
      pendingResult = result
      lock.unlock()
      return
    }

    self.continuation = nil
    lock.unlock()
    continuation.resume(with: result)
  }
}
