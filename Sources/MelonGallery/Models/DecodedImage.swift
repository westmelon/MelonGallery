@preconcurrency import AppKit

struct DecodedImage: @unchecked Sendable {
  // Decoded off the main thread, then displayed without mutating the image.
  let image: NSImage
  let source: ImageDecodingSource
}

enum ImageDecodingSource: Sendable, Equatable {
  case image
  case fullResolutionRAW
  case embeddedPreview
  case systemPreview

  var title: String? {
    switch self {
    case .image: nil
    case .fullResolutionRAW: L10n.fullResolutionRAW
    case .embeddedPreview: L10n.embeddedRAWPreview
    case .systemPreview: L10n.systemRAWPreview
    }
  }
}
