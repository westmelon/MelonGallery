import CoreGraphics
import Foundation
import RAWImageTransfer
import XCTest
@testable import MelonGallery

final class RAWImageTransferTests: XCTestCase {
  func testMappedTransferPreserves16BitPixelsAndColorAfterFileRemoval() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (original, bytes) = try fixture()
    try RAWImageTransfer.write(original, source: .fullResolutionRAW, to: directory)
    let (mapped, source) = try RAWImageTransfer.read(from: directory)
    try FileManager.default.removeItem(at: directory)

    XCTAssertEqual(source, .fullResolutionRAW)
    XCTAssertEqual(mapped.width, original.width)
    XCTAssertEqual(mapped.height, original.height)
    XCTAssertEqual(mapped.bitsPerComponent, 16)
    XCTAssertEqual(mapped.bitsPerPixel, original.bitsPerPixel)
    XCTAssertEqual(mapped.bitmapInfo, original.bitmapInfo)
    XCTAssertEqual(mapped.colorSpace?.name, original.colorSpace?.name)
    XCTAssertEqual(mapped.colorSpace?.copyICCData(), original.colorSpace?.copyICCData())
    XCTAssertEqual(try XCTUnwrap(mapped.dataProvider?.data) as Data, bytes)
  }

  func testTruncatedPixelTransferIsRejected() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try RAWImageTransfer.write(fixture().0, source: .fullResolutionRAW, to: directory)
    try Data([0]).write(to: directory.appendingPathComponent("pixels"))
    XCTAssertThrowsError(try RAWImageTransfer.read(from: directory))
  }

  func testRunningDecoderCancellationTerminatesWorkerAndCleansTemporaryFiles() async throws {
    guard let samplePath = ProcessInfo.processInfo.environment["MELON_RW2_SAMPLE_DIR"] else {
      throw XCTSkip("Set MELON_RW2_SAMPLE_DIR to verify cancellation of a running RAW decoder.")
    }
    let before = try transferDirectories()
    let request = IsolatedRAWDecoder.Request()
    let task = Task.detached {
      request.decode(at: URL(fileURLWithPath: samplePath).appendingPathComponent("P1231034.RW2"))
    }
    let deadline = ContinuousClock.now + .seconds(5)
    while !request.isRunning && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(2))
    }
    XCTAssertTrue(request.isRunning, "The test must cancel after the decoder has launched.")
    request.cancel()
    let result = await task.value
    XCTAssertNil(result)
    XCTAssertFalse(request.isRunning)
    XCTAssertEqual(try transferDirectories(), before)
  }

  func testDecoderTimeoutReturnsFailureAndAllowsRetry() async throws {
    guard let samplePath = ProcessInfo.processInfo.environment["MELON_RW2_SAMPLE_DIR"] else {
      throw XCTSkip("Set MELON_RW2_SAMPLE_DIR to verify RAW decoder timeout and retry.")
    }
    let url = URL(fileURLWithPath: samplePath).appendingPathComponent("P1220976.RW2")
    let request = IsolatedRAWDecoder.Request(timeoutInterval: 0)
    let expired = await Task.detached { request.decode(at: url) }.value
    XCTAssertNil(expired)
    XCTAssertFalse(request.isRunning)
    let retried = await IsolatedRAWDecoder.decode(at: url)
    XCTAssertEqual(retried?.source, .fullResolutionRAW)
    XCTAssertEqual(retried?.image.size, NSSize(width: 6000, height: 4000))
  }

  private func fixture() throws -> (CGImage, Data) {
    let samples: [UInt16] = [12345, 23456, 34567, 65535, 45678, 56789, 6789, 65535]
    let bytes = samples.withUnsafeBytes { Data($0) }
    let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let image = try XCTUnwrap(CGImage(
      width: 2, height: 1, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: 16,
      space: space, bitmapInfo: [.byteOrder16Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    ))
    return (image, bytes)
  }

  private func transferDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
      .filter { $0.hasPrefix("MelonRAWDecode-") })
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MelonTransferTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }
}
