import AppKit
import SwiftUI

struct ZoomableImageView: NSViewRepresentable {
  let image: NSImage
  @Binding var magnification: CGFloat
  let showsGrid: Bool
  let fitRequest: Int
  let actualSizeRequest: Int
  var viewportLink: ImageViewportLink? = nil
  var startsAtActualSize = false

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ZoomScrollView()
    let clipView = CenteringClipView()
    let imageView = PannableImageView()

    scrollView.contentView = clipView
    scrollView.documentView = imageView
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.01
    scrollView.maxMagnification = 8
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.scrollerKnobStyle = .default
    scrollView.horizontalScroller?.controlSize = .small
    scrollView.verticalScroller?.controlSize = .small
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    scrollView.drawsBackground = false

    imageView.imageAlignment = .alignCenter
    imageView.imageScaling = .scaleNone
    imageView.scrollView = scrollView
    imageView.onDoubleClick = { [weak coordinator = context.coordinator] in
      coordinator?.toggleActualSize()
    }
    scrollView.onContentSizeChange = { [weak coordinator = context.coordinator] in
      coordinator?.contentSizeDidChange()
    }
    if viewportLink != nil {
      scrollView.onViewportChange = { [weak coordinator = context.coordinator] in
        coordinator?.viewportDidChange()
      }
      scrollView.onInteraction = { [weak coordinator = context.coordinator] in
        coordinator?.beginInteraction()
      }
      imageView.onPan = { [weak coordinator = context.coordinator] in
        coordinator?.beginInteraction()
        coordinator?.viewportDidChange()
      }
    }
    scrollView.gridOverlay.imageView = imageView
    scrollView.addSubview(scrollView.gridOverlay, positioned: .above, relativeTo: clipView)
    scrollView.gridOverlay.isHidden = !showsGrid

    context.coordinator.attach(to: scrollView, imageView: imageView)
    viewportLink?.register(context.coordinator)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let isInitialUpdate = context.coordinator.fitRequest == -1
    context.coordinator.parent = self
    context.coordinator.update(image: image)
    (scrollView as? ZoomScrollView)?.gridOverlay.isHidden = !showsGrid

    if context.coordinator.fitRequest != fitRequest {
      context.coordinator.fitRequest = fitRequest
      context.coordinator.actualSizeRequest = actualSizeRequest
      context.coordinator.fitImage()
      if isInitialUpdate && startsAtActualSize {
        context.coordinator.setMagnification(1)
      }
    } else if context.coordinator.actualSizeRequest != actualSizeRequest {
      context.coordinator.actualSizeRequest = actualSizeRequest
      context.coordinator.fitRequest = fitRequest
      context.coordinator.setMagnification(1)
    } else if abs(scrollView.magnification - magnification) > 0.001 {
      context.coordinator.setMagnification(magnification, updateBinding: false)
    }
  }

  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    coordinator.parent.viewportLink?.unregister(coordinator)
    coordinator.clearImage()
    NotificationCenter.default.removeObserver(coordinator)
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: ZoomableImageView
    var fitRequest = -1
    var actualSizeRequest = -1

    private weak var scrollView: ZoomScrollView?
    private weak var imageView: PannableImageView?
    private var imageIdentifier: ObjectIdentifier?
    private var isFitMode = true
    private var isUpdatingViewport = false

    var interactiveViewport: ImageViewport? {
      isFitMode ? nil : viewport
    }

    var viewport: ImageViewport? {
      guard let scrollView, let imageView,
            imageView.frame.width > 0, imageView.frame.height > 0 else { return nil }
      let center = visibleCenter(in: scrollView)
      return ImageViewport(
        magnification: scrollView.magnification,
        center: NSPoint(
          x: center.x / imageView.frame.width,
          y: center.y / imageView.frame.height
        )
      )
    }

    func apply(viewport: ImageViewport) {
      guard let scrollView, let imageView,
            imageView.frame.width > 0, imageView.frame.height > 0 else { return }
      isUpdatingViewport = true
      isFitMode = false
      let scale = min(max(viewport.magnification, scrollView.minMagnification), scrollView.maxMagnification)
      scrollView.setMagnification(scale, centeredAt: visibleCenter(in: scrollView))
      let bounds = scrollView.contentView.bounds
      let origin = NSPoint(
        x: viewport.center.x * imageView.frame.width - bounds.width / 2,
        y: viewport.center.y * imageView.frame.height - bounds.height / 2
      )
      let constrained = scrollView.contentView.constrainBoundsRect(NSRect(origin: origin, size: bounds.size))
      scrollView.contentView.scroll(to: constrained.origin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
      isUpdatingViewport = false
      updateMagnificationBinding()
    }

    func beginInteraction() {
      isFitMode = false
    }

    func viewportDidChange() {
      guard !isUpdatingViewport, !isFitMode else { return }
      updateMagnificationBinding()
      parent.viewportLink?.synchronize(from: self)
    }

    init(_ parent: ZoomableImageView) {
      self.parent = parent
    }

    fileprivate func attach(to scrollView: ZoomScrollView, imageView: PannableImageView) {
      self.scrollView = scrollView
      self.imageView = imageView
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(magnificationDidEnd),
        name: NSScrollView.didEndLiveMagnifyNotification,
        object: scrollView
      )
    }

    func update(image: NSImage) {
      let identifier = ObjectIdentifier(image)
      guard identifier != imageIdentifier else {
        return
      }

      imageIdentifier = identifier
      imageView?.setImage(image)
      imageView?.frame = NSRect(origin: .zero, size: image.size)
      scrollView?.gridOverlay.needsDisplay = true
      isFitMode = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if isFitMode { fitImage() }
        parent.viewportLink?.alignLoadedViewport(self)
      }
    }

    func clearImage() {
      imageView?.clearImage()
      imageIdentifier = nil
    }

    func contentSizeDidChange() {
      if isFitMode {
        fitImage()
      }
    }

    func fitImage() {
      guard let scrollView,
            let imageView,
            imageView.frame.width > 0,
            imageView.frame.height > 0 else {
        return
      }

      let availableSize = scrollView.contentSize
      guard availableSize.width > 1, availableSize.height > 1 else {
        return
      }
      let fitScale = min(
        availableSize.width / imageView.frame.width,
        availableSize.height / imageView.frame.height,
        1
      )
      scrollView.minMagnification = 0.01
      isFitMode = true
      setMagnification(fitScale, preservesFitMode: true)
    }

    func toggleActualSize() {
      guard let scrollView else {
        return
      }
      if abs(scrollView.magnification - 1) < 0.01 {
        fitImage()
        parent.viewportLink?.fitPeers(of: self)
      } else {
        setMagnification(1)
      }
    }

    func setMagnification(
      _ value: CGFloat,
      updateBinding: Bool = true,
      preservesFitMode: Bool = false
    ) {
      guard let scrollView else {
        return
      }
      if !preservesFitMode {
        isFitMode = false
      }
      let clampedValue = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
      isUpdatingViewport = true
      scrollView.setMagnification(clampedValue, centeredAt: visibleCenter(in: scrollView))
      scrollView.gridOverlay.needsDisplay = true
      isUpdatingViewport = false
      if updateBinding {
        updateMagnificationBinding()
      }
      if !preservesFitMode {
        parent.viewportLink?.synchronize(from: self)
      }
    }

    private func updateMagnificationBinding() {
      DispatchQueue.main.async { [weak self] in
        guard let self, let scrollView,
              abs(parent.magnification - scrollView.magnification) > 0.001 else { return }
        parent.magnification = scrollView.magnification
      }
    }

    private func visibleCenter(in scrollView: NSScrollView) -> NSPoint {
      let bounds = scrollView.contentView.bounds
      return NSPoint(x: bounds.midX, y: bounds.midY)
    }

    @objc private func magnificationDidEnd() {
      guard let scrollView else {
        return
      }
      isFitMode = false
      updateMagnificationBinding()
      parent.viewportLink?.synchronize(from: self)
      scrollView.gridOverlay.needsDisplay = true
    }
  }
}

private final class ZoomScrollView: NSScrollView {
  var onContentSizeChange: (() -> Void)?
  var onViewportChange: (() -> Void)?
  var onInteraction: (() -> Void)?
  let gridOverlay = ImageGridOverlayView()
  private var previousContentSize = NSSize.zero

  override func layout() {
    super.layout()
    if gridOverlay.frame != contentView.frame {
      gridOverlay.frame = contentView.frame
    }
    gridOverlay.needsDisplay = true
    let newSize = contentSize
    guard newSize != previousContentSize else {
      return
    }
    previousContentSize = newSize
    onContentSizeChange?()
  }

  override func reflectScrolledClipView(_ cView: NSClipView) {
    super.reflectScrolledClipView(cView)
    gridOverlay.needsDisplay = true
    onViewportChange?()
  }

  override func scrollWheel(with event: NSEvent) {
    onInteraction?()
    super.scrollWheel(with: event)
    onViewportChange?()
  }

  override func magnify(with event: NSEvent) {
    onInteraction?()
    super.magnify(with: event)
    onViewportChange?()
  }
}

private final class ImageGridOverlayView: NSView {
  weak var imageView: PannableImageView?

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    guard let imageView, imageView.cgImage != nil else { return }
    let imageRect = imageView.convert(imageView.bounds, to: self)
    guard imageRect.width > 0, imageRect.height > 0 else { return }

    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(rect: imageRect).addClip()

    let pixelScale = window?.backingScaleFactor ?? 2
    func pixelCenter(_ position: CGFloat) -> CGFloat {
      (floor(position * pixelScale) + 0.5) / pixelScale
    }
    let thirds = NSBezierPath()
    for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
      let x = pixelCenter(imageRect.minX + imageRect.width * fraction)
      let y = pixelCenter(imageRect.minY + imageRect.height * fraction)
      thirds.move(to: NSPoint(x: x, y: imageRect.minY))
      thirds.line(to: NSPoint(x: x, y: imageRect.maxY))
      thirds.move(to: NSPoint(x: imageRect.minX, y: y))
      thirds.line(to: NSPoint(x: imageRect.maxX, y: y))
    }
    NSColor.black.withAlphaComponent(0.55).setStroke()
    thirds.lineWidth = 3 / pixelScale
    thirds.stroke()
    NSColor.white.withAlphaComponent(0.85).setStroke()
    thirds.lineWidth = 1 / pixelScale
    thirds.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
  }
}

private final class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var bounds = super.constrainBoundsRect(proposedBounds)
    guard let documentView else {
      return bounds
    }

    if documentView.frame.width < bounds.width {
      bounds.origin.x = (documentView.frame.width - bounds.width) / 2
    }
    if documentView.frame.height < bounds.height {
      bounds.origin.y = (documentView.frame.height - bounds.height) / 2
    }
    return bounds
  }
}

private final class PannableImageView: NSImageView {
  fileprivate var cgImage: CGImage?
  weak var scrollView: NSScrollView?
  var onDoubleClick: (() -> Void)?
  var onPan: (() -> Void)?
  private var dragStartLocation: NSPoint?
  private var dragStartOrigin: NSPoint?

  func setImage(_ image: NSImage) {
    cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    self.image = nil
    needsDisplay = true
  }

  func clearImage() {
    cgImage = nil
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let cgImage, let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.interpolationQuality = .high
    context.draw(cgImage, in: bounds)
    context.restoreGState()
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      onDoubleClick?()
      return
    }
    dragStartLocation = event.locationInWindow
    dragStartOrigin = scrollView?.contentView.bounds.origin
  }

  override func mouseDragged(with event: NSEvent) {
    guard let scrollView,
          let dragStartLocation,
          let dragStartOrigin else {
      return
    }

    let currentLocation = event.locationInWindow
    let scale = max(scrollView.magnification, 0.01)
    var origin = dragStartOrigin
    origin.x -= (currentLocation.x - dragStartLocation.x) / scale
    origin.y -= (currentLocation.y - dragStartLocation.y) / scale
    let proposedBounds = NSRect(origin: origin, size: scrollView.contentView.bounds.size)
    let constrainedOrigin = scrollView.contentView.constrainBoundsRect(proposedBounds).origin

    var rebasedLocation = dragStartLocation
    var rebasedOrigin = dragStartOrigin
    if abs(constrainedOrigin.x - origin.x) > 0.001 {
      rebasedLocation.x = currentLocation.x
      rebasedOrigin.x = constrainedOrigin.x
    }
    if abs(constrainedOrigin.y - origin.y) > 0.001 {
      rebasedLocation.y = currentLocation.y
      rebasedOrigin.y = constrainedOrigin.y
    }
    self.dragStartLocation = rebasedLocation
    self.dragStartOrigin = rebasedOrigin

    let currentOrigin = scrollView.contentView.bounds.origin
    guard abs(currentOrigin.x - constrainedOrigin.x) > 0.001
            || abs(currentOrigin.y - constrainedOrigin.y) > 0.001 else {
      return
    }

    scrollView.contentView.scroll(to: constrainedOrigin)
    scrollView.reflectScrolledClipView(scrollView.contentView)
    onPan?()
  }

  override func mouseUp(with event: NSEvent) {
    dragStartLocation = nil
    dragStartOrigin = nil
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }
}
