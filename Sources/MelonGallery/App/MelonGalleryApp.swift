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
        .environment(\.locale, store.appLanguage.locale)
        .id(store.appLanguage)
        .background(MainWindowRegistrationView())
        .onAppear {
          appDelegate.configureMemoryReclamation(thumbnails: store.thumbnailService)
        }
    }
    .commands {
      GalleryCommands(store: store)
    }

    Settings {
      SettingsView(store: store)
        .id(store.appLanguage)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var mainWindow: NSWindow?
  private var closeWindowMonitor: Any?
  private var memoryReclaimer: IdleMemoryReclaimer?

  func configureMemoryReclamation(thumbnails: ThumbnailService) {
    guard memoryReclaimer == nil else { return }
    let reclaimer = IdleMemoryReclaimer(thumbnails: thumbnails)
    memoryReclaimer = reclaimer
    reclaimer.start()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    closeWindowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self,
            event.keyCode == 13,
            event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
            let window = NSApp.keyWindow,
            window === self.mainWindow || window.title == L10n.appName else {
        return event
      }

      self.registerMainWindow(window)
      window.orderOut(nil)
      return nil
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    memoryReclaimer?.stop()
    if let closeWindowMonitor {
      NSEvent.removeMonitor(closeWindowMonitor)
    }
  }

  func registerMainWindow(_ window: NSWindow) {
    mainWindow = window
    window.isReleasedWhenClosed = false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showMainWindow(for: sender)
    return true
  }

  private func showMainWindow(for application: NSApplication) {
    let window = mainWindow ?? application.windows.first { $0.title == L10n.appName }
    guard let window else {
      application.activate(ignoringOtherApps: true)
      return
    }

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    if !window.isVisible {
      window.orderFront(nil)
    }
    window.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
  }
}

private struct MainWindowRegistrationView: NSViewRepresentable {
  func makeNSView(context: Context) -> MainWindowRegistrationNSView {
    MainWindowRegistrationNSView()
  }

  func updateNSView(_ nsView: MainWindowRegistrationNSView, context: Context) {}
}

private final class MainWindowRegistrationNSView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window,
          let appDelegate = NSApp.delegate as? AppDelegate else {
      return
    }
    appDelegate.registerMainWindow(window)
  }
}
