import Foundation

struct ImageMetadataRawGroup: Identifiable, Hashable, Sendable {
  let name: String
  let fields: [ImageMetadataRawField]

  var id: String {
    name
  }
}

struct ImageMetadataRawField: Identifiable, Hashable, Sendable {
  let key: String
  let value: String

  var id: String {
    "\(key)=\(value)"
  }
}

struct ImageMetadata: Hashable, Sendable {
  var dateTaken: Date?
  var pixelWidth: Int?
  var pixelHeight: Int?
  var formatName: String
  var cameraMake: String?
  var cameraModel: String?
  var lensModel: String?
  var iso: Int?
  var aperture: Double?
  var exposureTime: Double?
  var focalLength: Double?
  var hasGPS: Bool
  var rawGroups: [ImageMetadataRawGroup]

  static func empty(formatName: String = "-") -> ImageMetadata {
    ImageMetadata(
      dateTaken: nil,
      pixelWidth: nil,
      pixelHeight: nil,
      formatName: formatName,
      cameraMake: nil,
      cameraModel: nil,
      lensModel: nil,
      iso: nil,
      aperture: nil,
      exposureTime: nil,
      focalLength: nil,
      hasGPS: false,
      rawGroups: []
    )
  }
}
