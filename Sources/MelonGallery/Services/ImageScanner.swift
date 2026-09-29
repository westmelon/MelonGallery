import Foundation

struct ImageScanner: Sendable {
  private static let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "bmp", "pdf", "rw2"
  ]

  func scanFolder(_ folder: URL, recursive: Bool) async throws -> [ImageItem] {
    let worker = Task.detached(priority: .userInitiated) {
      try Self.scan(folder: folder, recursive: recursive)
    }

    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private static func scan(folder: URL, recursive: Bool) throws -> [ImageItem] {
    let resourceKeys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .contentModificationDateKey,
      .fileSizeKey
    ]

    if recursive {
      return try scanRecursively(folder: folder, resourceKeys: resourceKeys)
    }

    return try FileManager.default
      .contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles]
      )
      .compactMap(makeImageItem)
  }

  private static func scanRecursively(
    folder: URL,
    resourceKeys: Set<URLResourceKey>
  ) throws -> [ImageItem] {
    guard let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: Array(resourceKeys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    var items: [ImageItem] = []
    for case let fileURL as URL in enumerator {
      try Task.checkCancellation()
      if let item = makeImageItem(from: fileURL) {
        items.append(item)
      }
    }
    return items
  }

  private static func makeImageItem(from url: URL) -> ImageItem? {
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
      return nil
    }

    guard let values = try? url.resourceValues(forKeys: [
      .isRegularFileKey,
      .contentModificationDateKey,
      .fileSizeKey
    ]), values.isRegularFile == true else {
      return nil
    }

    let metadata = ImageMetadataReader.readMetadata(for: url)

    return ImageItem(
      url: url.standardizedFileURL,
      fileSize: Int64(values.fileSize ?? 0),
      modifiedAt: values.contentModificationDate,
      metadata: metadata
    )
  }
}
