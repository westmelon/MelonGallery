import Darwin
import Foundation

final class FolderMonitor: @unchecked Sendable {
  private let queue = DispatchQueue(label: "MelonGallery.FolderMonitor")
  private let stateLock = NSLock()
  private var sources: [DispatchSourceFileSystemObject] = []
  private var pendingChange: DispatchWorkItem?
  private var onChange: (@Sendable () -> Void)?
  private var generation = 0

  func start(folder: URL, recursive: Bool, onChange: @escaping @Sendable () -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    stopLocked()
    self.onChange = onChange
    let currentGeneration = generation

    let folders = recursive ? monitoredFolders(in: folder) : [folder]
    sources = folders.compactMap { folder in
      makeSource(for: folder, generation: currentGeneration)
    }
  }

  func stop() {
    stateLock.lock()
    defer { stateLock.unlock() }
    stopLocked()
  }

  // 调用方持有 stateLock；取消处理器只负责关闭文件描述符。
  private func stopLocked() {
    generation += 1
    let pendingChange = self.pendingChange
    let activeSources = sources
    self.pendingChange = nil
    sources = []
    onChange = nil
    pendingChange?.cancel()
    activeSources.forEach { $0.cancel() }
  }

  private func monitoredFolders(in root: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return [root]
    }

    var folders = [root]
    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isDirectory == true,
            values.isSymbolicLink != true else {
        continue
      }
      folders.append(url)
    }
    return folders
  }

  private func makeSource(for folder: URL, generation: Int) -> DispatchSourceFileSystemObject? {
    let descriptor = open(folder.path, O_EVTONLY)
    guard descriptor >= 0 else {
      return nil
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
      queue: queue
    )
    source.setEventHandler { [weak self] in
      self?.scheduleChange(for: generation)
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    return source
  }

  private func scheduleChange(for expectedGeneration: Int) {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard generation == expectedGeneration else { return }
    pendingChange?.cancel()
    let currentGeneration = generation
    let workItem = DispatchWorkItem { [weak self] in
      self?.fireChange(for: currentGeneration)
    }
    pendingChange = workItem
    queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: workItem)
  }

  private func fireChange(for expectedGeneration: Int) {
    stateLock.lock()
    guard generation == expectedGeneration else {
      stateLock.unlock()
      return
    }
    let callback = onChange
    stateLock.unlock()
    callback?()
  }

  deinit {
    stop()
  }
}
