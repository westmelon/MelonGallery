import AppKit
import SwiftUI

@main
struct MelonGalleryApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store = GalleryStore()

  var body: some Scene {
    WindowGroup(L10n.appName, id: "main") {
      ContentView(store: store)
        .frame(minWidth: 920, minHeight: 560)
    }
    .commands {
      GalleryCommands(store: store)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}
