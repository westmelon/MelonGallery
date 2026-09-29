import AppKit
import SwiftUI

struct KeyboardCaptureView: NSViewRepresentable {
  var focusToken: Int
  var onKeyDown: (NSEvent) -> Bool

  init(focusToken: Int = 0, onKeyDown: @escaping (NSEvent) -> Bool) {
    self.focusToken = focusToken
    self.onKeyDown = onKeyDown
  }

  func makeNSView(context: Context) -> KeyCaptureNSView {
    KeyCaptureNSView(focusToken: focusToken, onKeyDown: onKeyDown)
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onKeyDown = onKeyDown
    if nsView.focusToken != focusToken {
      nsView.focusToken = focusToken
      nsView.requestFocus()
      return
    }

    guard !(nsView.window?.firstResponder is NSTextView) else {
      return
    }
    nsView.requestFocus()
  }
}

final class KeyCaptureNSView: NSView {
  var focusToken: Int
  var onKeyDown: (NSEvent) -> Bool

  init(focusToken: Int, onKeyDown: @escaping (NSEvent) -> Bool) {
    self.focusToken = focusToken
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
