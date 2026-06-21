import AppKit
import SwiftUI

@MainActor
final class SlideshowPresenter {
  private var window: NSWindow?
  private var windowDelegate: WindowDelegate?
  private var session: SlideshowSession?
  private var closingReferences: [ClosingReferences] = []

  func show(
    items: [ImageItem],
    startingAt startID: ImageItem.ID?,
    store: GalleryStore,
    autoplay: Bool = true
  ) {
    guard !items.isEmpty else {
      return
    }

    close()

    let session = SlideshowSession(items: items, startingAt: startID)
    let rootView = SlideshowView(session: session, store: store, autoplay: autoplay) { [weak self] in
      self?.close()
    }

    let window = NSWindow(
      contentRect: initialContentRect(for: session.currentItem),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    let delegate = WindowDelegate { [weak self] delegate, closingWindow in
      self?.windowWillClose(closingWindow, delegate: delegate)
    }

    window.title = autoplay ? L10n.slideshow : L10n.openPreview
    window.titleVisibility = .hidden
    window.toolbarStyle = .unifiedCompact
    window.minSize = NSSize(width: 640, height: 420)
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(rootView: rootView)
    window.delegate = delegate
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    self.session = session
    self.window = window
    self.windowDelegate = delegate

    if autoplay {
      session.start()
    }
  }

  func close() {
    guard let window else {
      session?.stop()
      session = nil
      return
    }

    session?.stop()
    window.close()
  }

  private func windowWillClose(_ closingWindow: NSWindow?, delegate: WindowDelegate) {
    session?.stop()

    closingReferences.append(
      ClosingReferences(
        window: closingWindow,
        delegate: delegate,
        session: session
      )
    )

    if let closingWindow, window === closingWindow {
      window = nil
      session = nil
    }

    Task { @MainActor [weak self, weak delegate] in
      guard let self, let delegate else {
        return
      }
      releaseClosingReferences(for: delegate)
    }
  }

  private func releaseClosingReferences(for delegate: WindowDelegate) {
    closingReferences.removeAll { references in
      if references.delegate === delegate {
        references.window?.delegate = nil
        return true
      }
      return false
    }

    if windowDelegate === delegate {
      windowDelegate = nil
    }
  }

  private func initialContentRect(for item: ImageItem?) -> NSRect {
    let defaultSize = NSSize(width: 980, height: 680)
    let minimumSize = NSSize(width: 640, height: 420)

    guard let item,
          !item.playsAsAnimation,
          let pixelWidth = item.pixelWidth,
          let pixelHeight = item.pixelHeight,
          pixelWidth > 0,
          pixelHeight > 0,
          let visibleFrame = NSScreen.main?.visibleFrame else {
      return NSRect(origin: .zero, size: defaultSize)
    }

    let maximumSize = NSSize(width: visibleFrame.width * 0.9, height: visibleFrame.height * 0.9)
    let imageSize = NSSize(width: pixelWidth, height: pixelHeight)
    let fitScale = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height, 1)
    var proposedSize = NSSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)

    let minimumScale = max(minimumSize.width / proposedSize.width, minimumSize.height / proposedSize.height)
    if minimumScale > 1 {
      proposedSize.width *= minimumScale
      proposedSize.height *= minimumScale
    }

    let overflowScale = min(maximumSize.width / proposedSize.width, maximumSize.height / proposedSize.height, 1)
    proposedSize.width *= overflowScale
    proposedSize.height *= overflowScale
    proposedSize.width = min(max(proposedSize.width, minimumSize.width), maximumSize.width)
    proposedSize.height = min(max(proposedSize.height, minimumSize.height), maximumSize.height)

    return NSRect(origin: .zero, size: proposedSize)
  }
}

private struct ClosingReferences {
  let window: NSWindow?
  let delegate: WindowDelegate
  let session: SlideshowSession?
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
  private let onClose: (WindowDelegate, NSWindow?) -> Void

  init(onClose: @escaping (WindowDelegate, NSWindow?) -> Void) {
    self.onClose = onClose
  }

  func windowWillClose(_ notification: Notification) {
    onClose(self, notification.object as? NSWindow)
  }
}
