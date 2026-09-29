import AppKit
import Observation
import SwiftUI
import XCTest
@testable import MelonGallery

@MainActor
@Observable
private final class ViewportState {
  var leftScale: CGFloat = 1
  var rightScale: CGFloat = 1
  var fit = 0
  var actual = 0
  var rawDecode = 0
  var showRight = false
  var startsAtActualSize = false
  var decodedImage: NSImage?
  let link = ImageViewportLink()
  var leftImage = NSImage(size: NSSize(width: 1600, height: 1000))
  let rightImage = NSImage(size: NSSize(width: 900, height: 1500))
}

private struct ViewportFixture: View {
  @Bindable var state: ViewportState

  var body: some View {
    HStack(spacing: 1) {
      ZoomableImageView(
        image: state.leftImage, magnification: $state.leftScale,
        showsGrid: false, fitRequest: state.fit, actualSizeRequest: state.actual,
        viewportLink: state.link, startsAtActualSize: state.startsAtActualSize
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if state.showRight {
        ZoomableImageView(
          image: state.rightImage, magnification: $state.rightScale,
          showsGrid: false, fitRequest: state.fit, actualSizeRequest: state.actual,
          viewportLink: state.link
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .frame(minWidth: 900, minHeight: 480)
  }
}

private struct ProgressiveFixture: View {
  @Bindable var state: ViewportState
  let item: ImageItem

  var body: some View {
    ImagePreviewView(
      item: item, image: $state.decodedImage, magnification: $state.leftScale,
      showsGrid: false, fitRequest: state.fit, actualSizeRequest: state.actual,
      rawDecodeRequest: state.rawDecode
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
final class ZoomViewportTests: XCTestCase {
  func testDirectDrawingPreservesPixelOrientationAndImageReplacement() async throws {
    let state = ViewportState()
    func image(redOnBottom: Bool) throws -> NSImage {
      let context = try XCTUnwrap(CGContext(
        data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      for (y, red) in [(0, redOnBottom), (16, !redOnBottom)] {
        context.setFillColor(CGColor(srgbRed: red ? 1 : 0, green: red ? 0 : 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: y, width: 64, height: 16))
      }
      return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 64, height: 32))
    }
    state.leftImage = try image(redOnBottom: true)
    let (window, host) = makeWindow(state)
    defer { window.close() }
    for reversed in [false, true] {
      if reversed { state.leftImage = try image(redOnBottom: false) }
      await settle()
      let document = try XCTUnwrap(viewports(in: host).first?.documentView)
      let rendered = try XCTUnwrap(document.bitmapImageRepForCachingDisplay(in: document.bounds))
      document.cacheDisplay(in: document.bounds, to: rendered)
      let original = NSBitmapImageRep(cgImage: try XCTUnwrap(
        state.leftImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
      ))
      for y in [8, 24] {
        let expected = try XCTUnwrap(original.colorAt(x: 32, y: y)?.usingColorSpace(.sRGB))
        let actual = try XCTUnwrap(rendered.colorAt(
          x: rendered.pixelsWide / 2, y: y * rendered.pixelsHigh / 32
        )?.usingColorSpace(.sRGB))
        // Captured bitmaps may use the display profile; color regions must keep their orientation.
        XCTAssertEqual(actual.redComponent > actual.greenComponent,
                       expected.redComponent > expected.greenComponent)
        XCTAssertGreaterThan(actual.alphaComponent, 0.95)
      }
    }
  }

  func testRAWDecodeRequestedSeparatelyFromActualSize() async throws {
    guard let samplePath = ProcessInfo.processInfo.environment["MELON_RW2_SAMPLE_DIR"] else {
      throw XCTSkip("Set MELON_RW2_SAMPLE_DIR to verify the progressive RAW view.")
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MelonProgressiveView-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("portrait.RW2")
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: samplePath).appendingPathComponent("P1231034.RW2"), to: url
    )
    let state = ViewportState()
    let item = ImageItem(url: url, fileSize: 1, modifiedAt: nil, metadata: .empty())
    _ = NSApplication.shared
    let host = NSHostingView(rootView: ProgressiveFixture(state: state, item: item))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.setContentSize(NSSize(width: 800, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertNil(state.decodedImage)
    state.actual += 1
    try await Task.sleep(for: .seconds(1))
    XCTAssertNil(state.decodedImage, "1:1 must not trigger full RAW decoding.")
    state.rawDecode += 1
    let deadline = ContinuousClock.now + .seconds(10)
    while state.decodedImage == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    await settle()
    XCTAssertEqual(state.decodedImage?.size, NSSize(width: 4000, height: 6000))
    do {
      let scroll = try XCTUnwrap(viewports(in: host).first)
      XCTAssertEqual(scroll.documentView?.frame.size, NSSize(width: 4000, height: 6000))
      XCTAssertLessThan(scroll.magnification, 1, "RAW parsing should preserve fit-to-window until 1:1 is requested.")
      state.actual += 1
      await settle()
      XCTAssertEqual(scroll.magnification, 1, accuracy: 0.001)
    }

    weak let previousRAW = state.decodedImage
    state.rawDecode += 1
    await settle()
    XCTAssertTrue(state.decodedImage === previousRAW, "Repeated RAW requests must not restart a decoded image.")
    let jpegURL = URL(fileURLWithPath: samplePath).appendingPathComponent("P1220976.JPG")
    let jpeg = ImageItem(url: jpegURL, fileSize: 1, modifiedAt: nil, metadata: .empty())
    host.rootView = ProgressiveFixture(state: state, item: jpeg)
    let releaseDeadline = ContinuousClock.now + .seconds(5)
    while (previousRAW != nil || state.decodedImage?.size != NSSize(width: 6000, height: 4000))
      && ContinuousClock.now < releaseDeadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertEqual(state.decodedImage?.size, NSSize(width: 6000, height: 4000))
    XCTAssertNil(previousRAW, "Navigation must release the previous full RAW image.")
    host.rootView = ProgressiveFixture(state: state, item: item)
    try await Task.sleep(for: .seconds(1))
    XCTAssertNil(state.decodedImage, "Returning to RAW must not repeat the previous RAW decode request.")
    XCTAssertTrue(viewports(in: host).isEmpty)
  }

  func testInitialActualSizeSurvivesDeferredFit() async throws {
    let state = ViewportState()
    state.startsAtActualSize = true
    let (window, host) = makeWindow(state)
    defer { window.close() }
    await settle()
    let scroll = try XCTUnwrap(viewports(in: host).first)
    XCTAssertEqual(scroll.magnification, 1, accuracy: 0.001)
    XCTAssertEqual(scroll.documentView?.frame.size, state.leftImage.size)
    state.fit += 1
    await settle()
    XCTAssertLessThan(scroll.magnification, 1)
    state.actual += 1
    await settle()
    XCTAssertEqual(scroll.magnification, 1, accuracy: 0.001)
  }

  func testLateLoadedPeerAdoptsActiveZoom() async throws {
    let state = ViewportState()
    let (window, host) = makeWindow(state)
    defer { window.close() }
    await settle()
    state.leftScale = 2
    await settle()
    state.showRight = true
    await settle()
    let scrolls = viewports(in: host)
    XCTAssertEqual(scrolls.count, 2)
    for scroll in scrolls { XCTAssertEqual(scroll.magnification, 2, accuracy: 0.001) }
    XCTAssertEqual(state.rightScale, 2, accuracy: 0.001)
    state.fit += 1
    await settle()
    for scroll in scrolls { XCTAssertLessThan(scroll.magnification, 1) }
    XCTAssertNotEqual(scrolls[0].magnification, scrolls[1].magnification)
  }

  func testLateLoadedPeerRespectsIndependentMode() async throws {
    let state = ViewportState()
    state.link.isEnabled = false
    let (window, host) = makeWindow(state)
    defer { window.close() }
    await settle()
    state.leftScale = 2
    await settle()
    state.showRight = true
    await settle()
    let right = try XCTUnwrap(viewports(in: host).first { $0.documentView?.frame.width == 900 })
    XCTAssertLessThan(right.magnification, 1)
    XCTAssertEqual(state.leftScale, 2, accuracy: 0.001)
  }

  private func makeWindow(_ state: ViewportState) -> (NSWindow, NSHostingView<ViewportFixture>) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: ViewportFixture(state: state))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.setContentSize(NSSize(width: 1000, height: 650))
    window.orderFront(nil)
    return (window, host)
  }

  private func viewports(in view: NSView) -> [NSScrollView] {
    let current = (view as? NSScrollView).map { [$0] } ?? []
    return current + view.subviews.flatMap { viewports(in: $0) }
  }

  private func settle() async {
    try? await Task.sleep(for: .milliseconds(120))
  }
}
