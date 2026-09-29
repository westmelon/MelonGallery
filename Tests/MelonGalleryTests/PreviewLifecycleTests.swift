import AppKit
import XCTest
@testable import MelonGallery

@MainActor
final class PreviewLifecycleTests: XCTestCase {
  func testReplacingAndClosingPreviewReleasesContent() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MelonWindowTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let items = try ["left.png", "right.png"].map { name in
      let url = folder.appendingPathComponent(name)
      try data.write(to: url)
      return ImageItem(url: url, fileSize: Int64(data.count), modifiedAt: nil, metadata: .empty())
    }
    let store = GalleryStore()
    let presenter = SlideshowPresenter()
    defer { presenter.close() }
    let originalWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
    presenter.show(items: items, startingAt: items[0].id, store: store, autoplay: false)
    let preview = try XCTUnwrap(NSApp.windows.first { !originalWindows.contains(ObjectIdentifier($0)) })
    weak let previewContent = preview.contentViewController
    XCTAssertNotNil(previewContent)

    let beforeComparison = Set(NSApp.windows.map(ObjectIdentifier.init))
    presenter.showComparison(items: items, store: store)
    let comparison = try XCTUnwrap(NSApp.windows.first { !beforeComparison.contains(ObjectIdentifier($0)) })
    weak let comparisonContent = comparison.contentViewController
    await settle()
    // AppKit or callers may retain a closed window; its image view tree must still be detached.
    XCTAssertNil(preview.contentViewController)
    XCTAssertNil(previewContent)
    XCTAssertNotNil(comparisonContent)
    XCTAssertTrue(comparison.isVisible)

    presenter.close()
    await settle()
    XCTAssertNil(comparison.contentViewController)
    XCTAssertNil(comparisonContent)
  }

  private func settle() async {
    try? await Task.sleep(for: .milliseconds(150))
  }
}
