import AppKit

@MainActor
final class IdleMemoryReclaimer {
  private let thumbnails: ThumbnailService
  private var eventMonitor: Any?
  private var notifications: [NSObjectProtocol] = []
  private var pendingReclamation: Task<Void, Never>?

  init(thumbnails: ThumbnailService) {
    self.thumbnails = thumbnails
  }

  func start() {
    stop()
    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .magnify, .leftMouseDragged]
    ) { [weak self] event in
      self?.schedule()
      return event
    }
    for name in [NSWindow.willCloseNotification, NSApplication.didResignActiveNotification] {
      notifications.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.schedule() }
      })
    }
    schedule()
  }

  func stop() {
    pendingReclamation?.cancel()
    pendingReclamation = nil
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
    notifications.forEach(NotificationCenter.default.removeObserver)
    notifications.removeAll()
  }

  private func schedule() {
    pendingReclamation?.cancel()
    pendingReclamation = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(15))
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      thumbnails.clearMemoryCache()
    }
  }
}
