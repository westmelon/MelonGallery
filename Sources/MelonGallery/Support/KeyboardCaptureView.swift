import AppKit
import SwiftUI

struct KeyboardCaptureView: NSViewRepresentable {
  var onKeyDown: (NSEvent) -> Bool

  func makeNSView(context: Context) -> KeyCaptureNSView {
    KeyCaptureNSView(onKeyDown: onKeyDown)
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onKeyDown = onKeyDown
    nsView.requestFocus()
  }
}

final class KeyCaptureNSView: NSView {
  var onKeyDown: (NSEvent) -> Bool

  init(onKeyDown: @escaping (NSEvent) -> Bool) {
    self.onKeyDown = onKeyDown
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    requestFocus()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  func requestFocus() {
    DispatchQueue.main.async { [weak self] in
      guard let self,
            let window = self.window,
            window.firstResponder !== self else {
        return
      }
      window.makeFirstResponder(self)
    }
  }

  override func keyDown(with event: NSEvent) {
    if !onKeyDown(event) {
      super.keyDown(with: event)
    }
  }
}
