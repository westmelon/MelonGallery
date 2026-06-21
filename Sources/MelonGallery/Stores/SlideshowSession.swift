import Foundation
import Observation

@MainActor
@Observable
final class SlideshowSession {
  var items: [ImageItem]
  var index: Int
  var isPaused = false

  @ObservationIgnored private var timer: Timer?

  var currentItem: ImageItem? {
    guard items.indices.contains(index) else {
      return nil
    }
    return items[index]
  }

  var counterText: String {
    guard !items.isEmpty else {
      return "0 / 0"
    }
    return "\(index + 1) / \(items.count)"
  }

  init(items: [ImageItem], startingAt startID: ImageItem.ID?) {
    self.items = items
    if let startID, let startIndex = items.firstIndex(where: { $0.id == startID }) {
      self.index = startIndex
    } else {
      self.index = 0
    }
  }

  func start() {
    stop()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.advanceIfPlaying()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func togglePause() {
    isPaused.toggle()
  }

  func next() {
    guard !items.isEmpty else {
      return
    }
    index = (index + 1) % items.count
  }

  func previous() {
    guard !items.isEmpty else {
      return
    }
    index = (index - 1 + items.count) % items.count
  }

  @discardableResult
  func removeCurrentItem() -> Bool {
    guard items.indices.contains(index) else {
      return !items.isEmpty
    }

    items.remove(at: index)
    if index >= items.count {
      index = max(items.count - 1, 0)
    }

    return !items.isEmpty
  }

  private func advanceIfPlaying() {
    guard !isPaused else {
      return
    }
    next()
  }
}
