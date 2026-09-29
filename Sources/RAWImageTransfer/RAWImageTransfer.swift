import CoreGraphics
import Darwin
import Foundation

public enum RAWImageSource: String, Codable, Sendable {
  case fullResolutionRAW
  case embeddedPreview
  case systemPreview
}

public enum RAWImageTransfer {
  private struct Description: Codable {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let bytesPerRow: Int
    let bitmapInfo: UInt32
    let colorSpaceName: String?
    let colorProfile: Data?
    let renderingIntent: Int32
    let source: RAWImageSource
  }

  public static func write(_ image: CGImage, source: RAWImageSource, to directory: URL) throws {
    guard let pixels = image.dataProvider?.data, let colorSpace = image.colorSpace else {
      throw TransferError.invalidImage
    }
    let description = Description(
      width: image.width, height: image.height,
      bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
      bytesPerRow: image.bytesPerRow, bitmapInfo: image.bitmapInfo.rawValue,
      colorSpaceName: colorSpace.name.map { $0 as String },
      colorProfile: colorSpace.copyICCData().map { $0 as Data },
      renderingIntent: image.renderingIntent.rawValue, source: source
    )
    try (pixels as Data).write(to: directory.appendingPathComponent("pixels"))
    try JSONEncoder().encode(description).write(to: directory.appendingPathComponent("image.json"))
  }

  public static func read(from directory: URL) throws -> (CGImage, RAWImageSource) {
    let description = try JSONDecoder().decode(
      Description.self, from: Data(contentsOf: directory.appendingPathComponent("image.json"))
    )
    let (size, overflow) = description.bytesPerRow.multipliedReportingOverflow(by: description.height)
    guard description.width > 0, description.height > 0, description.bytesPerRow > 0,
          !overflow, size > 0 else { throw TransferError.invalidImage }
    let provider = try mappedProvider(at: directory.appendingPathComponent("pixels"), size: size)
    let namedSpace = description.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }
    let colorSpace = namedSpace ?? description.colorProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
    guard let colorSpace,
          let image = CGImage(
            width: description.width, height: description.height,
            bitsPerComponent: description.bitsPerComponent, bitsPerPixel: description.bitsPerPixel,
            bytesPerRow: description.bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: description.bitmapInfo), provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: CGColorRenderingIntent(rawValue: description.renderingIntent) ?? .defaultIntent
          ) else { throw TransferError.invalidImage }
    return (image, description.source)
  }

  private static func mappedProvider(at url: URL, size: Int) throws -> CGDataProvider {
    let descriptor = open(url.path, O_RDONLY)
    guard descriptor >= 0 else { throw TransferError.invalidImage }
    defer { close(descriptor) }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0, attributes.st_size >= size,
          let pixels = mmap(nil, size, PROT_READ, MAP_PRIVATE, descriptor, 0),
          pixels != MAP_FAILED else { throw TransferError.invalidImage }
    // Core Graphics owns the read-only mapping directly, without a Data/CFData bridge.
    guard let provider = CGDataProvider(dataInfo: nil, data: pixels, size: size, releaseData: { _, data, count in
      munmap(UnsafeMutableRawPointer(mutating: data), count)
    }) else {
      munmap(pixels, size)
      throw TransferError.invalidImage
    }
    return provider
  }

  private enum TransferError: Error {
    case invalidImage
  }
}
