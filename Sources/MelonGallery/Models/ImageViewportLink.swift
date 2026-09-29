import AppKit

struct ImageViewport {
  let magnification: CGFloat
  let center: NSPoint
}

@MainActor
final class ImageViewportLink {
  var isEnabled = true {
    didSet {
      if isEnabled, let lastSource {
        synchronize(from: lastSource)
      }
    }
  }

  private weak var first: ZoomableImageView.Coordinator?
  private weak var second: ZoomableImageView.Coordinator?
  private weak var lastSource: ZoomableImageView.Coordinator?

  func register(_ coordinator: ZoomableImageView.Coordinator) {
    if first == nil {
      first = coordinator
    } else if first !== coordinator {
      second = coordinator
    }
  }

  func unregister(_ coordinator: ZoomableImageView.Coordinator) {
    if first === coordinator { first = nil }
    if second === coordinator { second = nil }
    if lastSource === coordinator { lastSource = nil }
  }

  func alignLoadedViewport(_ coordinator: ZoomableImageView.Coordinator) {
    guard isEnabled, let lastSource, lastSource !== coordinator,
          let viewport = lastSource.interactiveViewport else { return }
    coordinator.apply(viewport: viewport)
  }

  func synchronize(from source: ZoomableImageView.Coordinator) {
    lastSource = source
    guard isEnabled, let viewport = source.viewport else { return }
    if first !== source { first?.apply(viewport: viewport) }
    if second !== source { second?.apply(viewport: viewport) }
  }

  func fitPeers(of source: ZoomableImageView.Coordinator) {
    guard isEnabled else { return }
    if first !== source { first?.fitImage() }
    if second !== source { second?.fitImage() }
  }
}
