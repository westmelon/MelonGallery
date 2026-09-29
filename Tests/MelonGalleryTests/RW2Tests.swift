@preconcurrency import AppKit
import ImageIO
import XCTest
@testable import MelonGallery

@MainActor
final class RW2Tests: XCTestCase {
  func testScannerHandlesRW2CaseRecursionAndUnsupportedFormats() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let nested = folder.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    for name in ["upper.RW2", "lower.rw2", "mixed.Rw2", "photo.JPG", "other.NEF"] {
      try Data("scan fixture".utf8).write(to: folder.appendingPathComponent(name))
    }
    try Data("scan fixture".utf8).write(to: nested.appendingPathComponent("portrait.RW2"))
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.RW2"), withIntermediateDirectories: true)

    let scanner = ImageScanner()
    let flat = try await scanner.scanFolder(folder, recursive: false)
    XCTAssertEqual(Set(flat.map(\.name)), ["upper.RW2", "lower.rw2", "mixed.Rw2", "photo.JPG"])
    let recursive = try await scanner.scanFolder(folder, recursive: true)
    XCTAssertEqual(recursive.count, 5)
    XCTAssertEqual(recursive.filter(\.isRAW).count, 4)
  }

  func testVisibilityPreservesFilesAndUsesVisibleSelection() async {
    let oldPreference = UserDefaults.standard.object(forKey: "showRAWFiles")
    defer { restorePreference(oldPreference) }
    let store = GalleryStore()
    let jpeg = item("PHOTO.JPG")
    let raw = item("PHOTO.RW2")
    store.items = [jpeg, raw]
    store.showRAWFiles = false
    store.clearFilters()
    XCTAssertEqual(store.items.count, 2)
    XCTAssertEqual(store.browsableItems, [jpeg])
    XCTAssertEqual(store.filteredItems, [jpeg])
    XCTAssertFalse(store.isFilterActive)
    store.selectAll()
    XCTAssertEqual(store.selectedItems, [jpeg])

    store.showRAWFiles = true
    store.selectAll()
    XCTAssertTrue(store.canCompareSelection)
    XCTAssertEqual(store.selectedItems.count, 2)
    store.showRAWFiles = false
    XCTAssertEqual(store.selectedItems, [jpeg])
    XCTAssertEqual(store.focusedItem, jpeg)
    XCTAssertFalse(store.canCompareSelection)
    XCTAssertEqual(store.items.count, 2)
  }

  func testRealRAWPreviewThumbnailsMetadataAndJPEGPixelSize() async throws {
    let folder = try sampleFolder()
    for (name, expectedSize) in [
      ("P1220976", NSSize(width: 6000, height: 4000)),
      ("P1231034", NSSize(width: 4000, height: 6000)),
      ("P1231036", NSSize(width: 6000, height: 4000))
    ] {
      let raw = folder.appendingPathComponent("\(name).RW2")
      let jpeg = folder.appendingPathComponent("\(name).JPG")
      let metadata = ImageMetadataReader.readMetadata(for: raw)
      XCTAssertEqual(metadata.cameraModel, "DC-S5M2")
      XCTAssertEqual(metadata.cameraMake, "Panasonic")
      XCTAssertEqual(metadata.lensModel, "LUMIX S 24-60/F2.8")
      XCTAssertNotNil(metadata.dateTaken)
      XCTAssertNotNil(metadata.iso)
      XCTAssertNotNil(metadata.aperture)
      XCTAssertNotNil(metadata.exposureTime)
      XCTAssertNotNil(metadata.focalLength)
      XCTAssertEqual(metadata.pixelWidth, 6000)
      XCTAssertEqual(metadata.pixelHeight, 4000)

      let rawPreview = await ImageDecoder.preview(at: raw)
      XCTAssertEqual(rawPreview?.source, .fullResolutionRAW)
      XCTAssertEqual(rawPreview?.image.size, expectedSize)
      let comparison = await ImageDecoder.comparisonImage(at: raw)
      XCTAssertEqual(comparison?.size, expectedSize)
      let jpegPreview = await ImageDecoder.displayImage(at: jpeg, maxPixelSize: 4096)
      XCTAssertEqual(jpegPreview?.size, expectedSize)

      let thumbnail = try XCTUnwrap(ImageDecoder.thumbnail(at: raw, maxPixelSize: 320))
      XCTAssertEqual(max(thumbnail.size.width, thumbnail.size.height), 320)
      XCTAssertEqual(thumbnail.size.width > thumbnail.size.height, expectedSize.width > expectedSize.height)
    }
  }

  func testMissingAndCorruptRAWReturnFailureThenAllowRetry() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = folder.appendingPathComponent("broken.RW2")
    let missingDirect = await RW2Decoder.decode(at: raw)
    XCTAssertNil(missingDirect)
    let missing = await ImageDecoder.preview(at: raw)
    XCTAssertNil(missing)
    try Data("not a RAW file".utf8).write(to: raw)
    let corruptDirect = await RW2Decoder.decode(at: raw)
    XCTAssertNil(corruptDirect)
    let corrupt = await ImageDecoder.preview(at: raw)
    XCTAssertNil(corrupt)

    let sample = try sampleFolder().appendingPathComponent("P1231034.RW2")
    try FileManager.default.removeItem(at: raw)
    try FileManager.default.copyItem(at: sample, to: raw)
    let retried = await ImageDecoder.preview(at: raw)
    XCTAssertEqual(retried?.source, .fullResolutionRAW)
    XCTAssertEqual(retried?.image.size, NSSize(width: 4000, height: 6000))
  }

  func testRenamedJPEGIsNotReportedAsFullResolutionRAW() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let disguised = folder.appendingPathComponent("renamed.RW2")
    try FileManager.default.copyItem(
      at: sampleFolder().appendingPathComponent("P1220976.JPG"), to: disguised
    )
    let disguisedDirect = await RW2Decoder.decode(at: disguised)
    XCTAssertNil(disguisedDirect)
    let preview = await ImageDecoder.preview(at: disguised)
    XCTAssertNotEqual(preview?.source, .fullResolutionRAW)
  }

  func testProgressivePreviewAndCacheReuseForLandscapeAndPortrait() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for (name, previewSize, fullSize) in [
      ("P1220976", NSSize(width: 1920, height: 1280), NSSize(width: 6000, height: 4000)),
      ("P1231034", NSSize(width: 1280, height: 1920), NSSize(width: 4000, height: 6000))
    ] {
      let url = folder.appendingPathComponent("\(name).RW2")
      try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("\(name).RW2"), to: url)
      var firstPreview: DecodedImage?
      let clock = ContinuousClock()
      let started = clock.now
      var previewTime: Duration?
      let decoded = await ImageDecoder.preview(at: url) { preview in
        firstPreview = preview
        previewTime = started.duration(to: clock.now)
      }
      let full = try XCTUnwrap(decoded)
      let fullTime = started.duration(to: clock.now)
      XCTAssertEqual(firstPreview?.source, .embeddedPreview)
      XCTAssertEqual(firstPreview?.image.size, previewSize)
      XCTAssertEqual(full.source, .fullResolutionRAW)
      XCTAssertEqual(full.image.size, fullSize)
      XCTAssertLessThan(try XCTUnwrap(previewTime), fullTime)

      let cachedStart = clock.now
      var emittedPreview = false
      let cachedResult = await ImageDecoder.preview(at: url) { _ in emittedPreview = true }
      let cached = try XCTUnwrap(cachedResult)
      let cachedTime = cachedStart.duration(to: clock.now)
      XCTAssertTrue(cached.image === full.image)
      XCTAssertFalse(emittedPreview)
      print("RAW latency \(name): first preview \(previewTime!), full \(fullTime), cached \(cachedTime)")
    }
  }

  func testRAWCanStopAfterEmbeddedPreview() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("embedded-only.RW2")
    try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("P1220976.RW2"), to: url)

    var emitted: DecodedImage?
    let result = await ImageDecoder.preview(at: url, onPreview: { preview in
      emitted = preview
    }, loadFullResolution: false)

    XCTAssertEqual(result?.source, .embeddedPreview)
    XCTAssertEqual(emitted?.source, .embeddedPreview)
    XCTAssertEqual(result?.image.size, NSSize(width: 1920, height: 1280))
  }

  func testUncachedRAWDoesNotRetainFullResolutionForLaterBrowsing() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("uncached.RW2")
    try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("P1220976.RW2"), to: url)

    let full = await ImageDecoder.preview(at: url, cachesFullResolution: false)
    XCTAssertEqual(full?.source, .fullResolutionRAW)
    let next = await ImageDecoder.preview(at: url, loadFullResolution: false)
    XCTAssertEqual(next?.source, .embeddedPreview)

    let cached = await ImageDecoder.preview(at: url)
    XCTAssertEqual(cached?.source, .fullResolutionRAW)
    let bypassed = await ImageDecoder.preview(at: url, loadFullResolution: false, cachesFullResolution: false)
    XCTAssertEqual(bypassed?.source, .embeddedPreview)
  }

  func testClearingThumbnailCacheKeepsDisplayedImageAndAllowsReload() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("thumbnail.RW2")
    try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("P1220976.RW2"), to: url)
    let service = ThumbnailService()
    let firstResult = await service.thumbnail(for: url, modifiedAt: nil, pointSize: 160, scale: 2)
    let displayed = try XCTUnwrap(firstResult)
    service.clearMemoryCache()
    let nextResult = await service.thumbnail(for: url, modifiedAt: nil, pointSize: 160, scale: 2)
    let reloaded = try XCTUnwrap(nextResult)
    XCTAssertFalse(displayed === reloaded)
    XCTAssertEqual(displayed.size, reloaded.size)
    XCTAssertEqual(max(displayed.size.width, displayed.size.height), 320)
  }

  func testCacheInvalidationAndRetryAfterFileChanges() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("changing.RW2")
    try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("P1220976.RW2"), to: url)
    let first = await ImageDecoder.preview(at: url)
    XCTAssertEqual(first?.source, .fullResolutionRAW)

    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
    var emittedPreview = false
    let changed = await ImageDecoder.preview(at: url) { _ in emittedPreview = true }
    XCTAssertTrue(emittedPreview)
    XCTAssertFalse(changed?.image === first?.image)

    try Data("corrupt RAW".utf8).write(to: url, options: .atomic)
    let broken = await ImageDecoder.preview(at: url)
    XCTAssertNil(broken)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.copyItem(at: sampleFolder().appendingPathComponent("P1231034.RW2"), to: url)
    let retried = await ImageDecoder.preview(at: url)
    XCTAssertEqual(retried?.image.size, NSSize(width: 4000, height: 6000))
    try FileManager.default.removeItem(at: url)
    let missing = await ImageDecoder.preview(at: url)
    XCTAssertNil(missing)
  }

  func testCancellationStopsProgressiveDecodeAndPublication() async throws {
    let url = try sampleFolder().appendingPathComponent("P1231036.RW2")
    let cancelled = Task { @MainActor in
      var emittedPreview = false
      let result = await ImageDecoder.preview(at: url) { _ in emittedPreview = true }
      XCTAssertNil(result)
      XCTAssertFalse(emittedPreview)
    }
    cancelled.cancel()
    await cancelled.value

    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let copy = folder.appendingPathComponent("cancel-after-preview.RW2")
    try FileManager.default.copyItem(at: url, to: copy)
    var task: Task<DecodedImage?, Never>?
    task = Task { @MainActor in
      await ImageDecoder.preview(at: copy) { _ in
        task?.cancel()
      }
    }
    let result = await task?.value
    XCTAssertNil(result)
    var emittedPreview = false
    let retry = await ImageDecoder.preview(at: copy) { _ in emittedPreview = true }
    XCTAssertTrue(emittedPreview)
    XCTAssertEqual(retry?.source, .fullResolutionRAW)
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MelonRAWTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func sampleFolder() throws -> URL {
    guard let path = ProcessInfo.processInfo.environment["MELON_RW2_SAMPLE_DIR"] else {
      throw XCTSkip("Set MELON_RW2_SAMPLE_DIR to the directory containing the three recorded S5M2 sample pairs.")
    }
    return URL(fileURLWithPath: path)
  }

  private func item(_ name: String) -> ImageItem {
    ImageItem(url: URL(fileURLWithPath: "/tmp/\(name)"), fileSize: 1, modifiedAt: nil, metadata: .empty())
  }

  private func restorePreference(_ value: Any?) {
    if let value {
      UserDefaults.standard.set(value, forKey: "showRAWFiles")
    } else {
      UserDefaults.standard.removeObject(forKey: "showRAWFiles")
    }
  }
}
