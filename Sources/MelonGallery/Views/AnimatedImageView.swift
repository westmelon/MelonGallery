import SwiftUI
import WebKit

struct AnimatedImageView: NSViewRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WKWebView {
    let webView = WKWebView()
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true
    webView.allowsBackForwardNavigationGestures = false
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    guard context.coordinator.currentURL != url else {
      return
    }

    context.coordinator.currentURL = url
    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var currentURL: URL?
  }
}
