import Foundation
import Observation

@MainActor
@Observable
final class SlideshowSession {
  var items: [ImageItem]
  var index: Int
  var isPaused = false
  private var displayedPair: ImageItem?

  @ObservationIgnored private var timer: Timer?

  var currentItem: ImageItem? {
    if let displayedPair { return displayedPair }
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
    displayedPair = nil
    guard !items.isEmpty else {
      return
    }
    index = (index + 1) % items.count
  }

  func previous() {
    displayedPair = nil
    guard !items.isEmpty else {
      return
    }
    index = (index - 1 + items.count) % items.count
  }

  @discardableResult
  func removeCurrentItem() -> Bool {
    if displayedPair != nil {
      let removedID = displayedPair?.id
      displayedPair = nil
      if let removedIndex = items.firstIndex(where: { $0.id == removedID }) {
        items.remove(at: removedIndex)
        if removedIndex < index { index -= 1 }
        index = min(index, max(items.count - 1, 0))
      }
      return !items.isEmpty
    }
    guard items.indices.contains(index) else {
      return !items.isEmpty
    }

    items.remove(at: index)
    if index >= items.count {
      index = max(items.count - 1, 0)
    }

    return !items.isEmpty
  }

  func showPairedImage(_ item: ImageItem) {
    displayedPair = items.indices.contains(index) && items[index].id == item.id ? nil : item
  }

  private func advanceIfPlaying() {
    guard !isPaused else {
      return
    }
    next()
  }
}
