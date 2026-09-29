@preconcurrency import AppKit
import Foundation

final class RAWPreviewCache: @unchecked Sendable {
  struct Version: Equatable, Sendable {
    let modifiedAt: Date?
    let fileSize: Int?

    init?(url: URL) {
      let freshURL = URL(fileURLWithPath: url.path)
      guard let values = try? freshURL.resourceValues(forKeys: [
        .isRegularFileKey, .contentModificationDateKey, .fileSizeKey
      ]), values.isRegularFile == true else { return nil }
      modifiedAt = values.contentModificationDate
      fileSize = values.fileSize
    }
  }

  private final class Entry: NSObject {
    let version: Version
    let decoded: DecodedImage

    init(version: Version, decoded: DecodedImage) {
      self.version = version
      self.decoded = decoded
    }
  }

  // NSCache is thread-safe; published images are immutable.
  private let entries = NSCache<NSString, Entry>()

  init() {
    entries.totalCostLimit = 256 * 1024 * 1024
    entries.countLimit = 2
  }

  func image(at url: URL, version: Version?) -> DecodedImage? {
    guard let version,
          let entry = entries.object(forKey: url.standardizedFileURL.path as NSString),
          entry.version == version else { return nil }
    return entry.decoded
  }

  func insert(_ decoded: DecodedImage, at url: URL, version: Version?) {
    guard decoded.source == .fullResolutionRAW,
          let version, version == Version(url: url),
          let pixels = decoded.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let cost = pixels.bytesPerRow * pixels.height
    guard cost <= entries.totalCostLimit else { return }
    entries.setObject(
      Entry(version: version, decoded: decoded),
      forKey: url.standardizedFileURL.path as NSString, cost: cost
    )
  }
}
