import Foundation
import ImageIO
import RAWImageTransfer

let arguments = CommandLine.arguments
guard arguments.count == 3 else { exit(2) }
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

func decode() throws {
  guard let source = CGImageSourceCreateWithURL(
    input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
  ), CGImageSourceGetType(source) as String? == "com.panasonic.rw2-raw-image" else { exit(3) }
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
  let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
  let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
  let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
  let swapsAxes = (5...8).contains(orientation)

  if width > 0, height > 0,
     let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
       kCGImageSourceCreateThumbnailFromImageAlways: true,
       kCGImageSourceCreateThumbnailWithTransform: true,
       kCGImageSourceShouldCacheImmediately: true,
       kCGImageSourceThumbnailMaxPixelSize: max(width, height)
     ] as CFDictionary) {
    let fullSize = image.width == (swapsAxes ? height : width)
      && image.height == (swapsAxes ? width : height)
    try RAWImageTransfer.write(image, source: fullSize ? .fullResolutionRAW : .systemPreview, to: output)
    return
  }
  guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: false,
    kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: max(width, height, 4096)
  ] as CFDictionary) else { exit(3) }
  try RAWImageTransfer.write(image, source: .embeddedPreview, to: output)
}

do {
  try autoreleasepool { try decode() }
} catch {
  exit(4)
}
