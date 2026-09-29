import Foundation
import XCTest
@testable import MelonGallery

final class FolderMonitorTests: XCTestCase, @unchecked Sendable {
  func testSwitchAndStopDiscardPendingChanges() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MelonMonitorTests-\(UUID().uuidString)")
    let first = root.appendingPathComponent("first")
    let second = root.appendingPathComponent("second")
    for folder in [first, second] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let monitor = FolderMonitor()
    defer { monitor.stop() }
    let oldCallback = expectation(description: "旧目录的延迟刷新被取消")
    oldCallback.isInverted = true
    monitor.start(folder: first, recursive: false) { oldCallback.fulfill() }
    try Data().write(to: first.appendingPathComponent("pending.jpg"))
    try await Task.sleep(for: .milliseconds(80))

    let newCallback = expectation(description: "新目录收到变更")
    monitor.start(folder: second, recursive: false) { newCallback.fulfill() }
    try Data().write(to: second.appendingPathComponent("new.jpg"))
    await fulfillment(of: [newCallback], timeout: 3)
    await fulfillment(of: [oldCallback], timeout: 0.4)

    let stoppedCallback = expectation(description: "停止后不再发送延迟刷新")
    stoppedCallback.isInverted = true
    monitor.start(folder: second, recursive: false) { stoppedCallback.fulfill() }
    try Data().write(to: second.appendingPathComponent("stopped.jpg"))
    try await Task.sleep(for: .milliseconds(80))
    monitor.stop()
    await fulfillment(of: [stoppedCallback], timeout: 0.5)
  }

  func testConcurrentLifecycleStillAllowsMonitoring() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MelonMonitorRaceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let monitor = FolderMonitor()
    defer { monitor.stop() }
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<40 {
        group.addTask {
          monitor.start(folder: root, recursive: false) {}
          try? Data().write(to: root.appendingPathComponent("\(index).jpg"))
          monitor.stop()
        }
      }
    }
    let callback = expectation(description: "并发启停后仍能正常监控")
    monitor.start(folder: root, recursive: false) { callback.fulfill() }
    try Data().write(to: root.appendingPathComponent("final.jpg"))
    await fulfillment(of: [callback], timeout: 3)
  }
}
