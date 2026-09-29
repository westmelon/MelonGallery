@preconcurrency import AppKit
import Darwin
import RAWImageTransfer

enum IsolatedRAWDecoder {
  static func decode(at url: URL) async -> DecodedImage? {
    let request = Request()
    return await withTaskCancellationHandler {
      guard !Task.isCancelled else { return nil }
      return await Task.detached(priority: .userInitiated) {
        request.decode(at: url)
      }.value
    } onCancel: {
      request.cancel()
    }
  }

  private static var executable: URL? {
    let bundle = Bundle.main.bundleURL
    let candidates = [
      bundle.appendingPathComponent("Contents/Helpers/MelonRAWDecoder"),
      Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        .appendingPathComponent("MelonRAWDecoder"),
      bundle.deletingLastPathComponent().appendingPathComponent("MelonRAWDecoder"),
      URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appendingPathComponent("MelonRAWDecoder")
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private final class BundleMarker: NSObject {}

  // Synchronize cancellation with launch so a cancelled request cannot leave a worker running.
  final class Request: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let timeoutInterval: TimeInterval
    private var cancelled = false

    init(timeoutInterval: TimeInterval = 30) {
      self.timeoutInterval = timeoutInterval
    }

    var isRunning: Bool { lock.withLock { process.isRunning } }

    func decode(at url: URL) -> DecodedImage? {
      guard let executable = IsolatedRAWDecoder.executable else { return nil }
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MelonRAWDecode-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        process.executableURL = executable
        process.arguments = [url.path, directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try lock.withLock {
          guard !cancelled else { throw CancellationError() }
          try process.run()
        }
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        guard lock.withLock({ !cancelled }), process.terminationReason == .exit,
              process.terminationStatus == 0 else { return nil }
        let (pixels, rawSource) = try RAWImageTransfer.read(from: directory)
        guard lock.withLock({ !cancelled }) else { return nil }
        let source: ImageDecodingSource = switch rawSource {
        case .fullResolutionRAW: .fullResolutionRAW
        case .embeddedPreview: .embeddedPreview
        case .systemPreview: .systemPreview
        }
        let image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
        image.cacheMode = .never
        return DecodedImage(image: image, source: source)
      } catch {
        return nil
      }
    }

    func cancel() {
      lock.withLock {
        cancelled = true
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
    }
  }
}
