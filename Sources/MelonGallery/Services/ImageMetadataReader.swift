import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageMetadataReader {
  static func readMetadata(for url: URL) -> ImageMetadata {
    let fallbackFormat = url.pathExtension.isEmpty ? "-" : url.pathExtension.uppercased()
    let sourceOptions = [
      kCGImageSourceShouldCache: false
    ] as CFDictionary

    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
      return .empty(formatName: fallbackFormat)
    }

    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

    let dateTaken = firstDate(from: [
      stringValue(exif[kCGImagePropertyExifDateTimeOriginal]),
      stringValue(exif[kCGImagePropertyExifDateTimeDigitized]),
      stringValue(tiff[kCGImagePropertyTIFFDateTime])
    ])

    return ImageMetadata(
      dateTaken: dateTaken,
      pixelWidth: intValue(properties[kCGImagePropertyPixelWidth]),
      pixelHeight: intValue(properties[kCGImagePropertyPixelHeight]),
      formatName: formatName(from: source) ?? fallbackFormat,
      cameraMake: stringValue(tiff[kCGImagePropertyTIFFMake]),
      cameraModel: stringValue(tiff[kCGImagePropertyTIFFModel]),
      lensModel: stringValue(exif[kCGImagePropertyExifLensModel]),
      iso: isoValue(exif[kCGImagePropertyExifISOSpeedRatings]),
      aperture: doubleValue(exif[kCGImagePropertyExifFNumber]),
      exposureTime: doubleValue(exif[kCGImagePropertyExifExposureTime]),
      focalLength: doubleValue(exif[kCGImagePropertyExifFocalLength]),
      hasGPS: !gps.isEmpty,
      rawGroups: rawGroups(properties: properties, tiff: tiff, exif: exif, gps: gps)
    )
  }

  private static func rawGroups(
    properties: [CFString: Any],
    tiff: [CFString: Any],
    exif: [CFString: Any],
    gps: [CFString: Any]
  ) -> [ImageMetadataRawGroup] {
    [
      rawGroup(name: "Image", fields: rawFields(from: properties, skippingDictionaries: true)),
      rawGroup(name: "TIFF", fields: rawFields(from: tiff)),
      rawGroup(name: "EXIF", fields: rawFields(from: exif)),
      rawGroup(name: "GPS", fields: rawFields(from: gps))
    ]
    .compactMap { $0 }
  }

  private static func rawGroup(name: String, fields: [ImageMetadataRawField]) -> ImageMetadataRawGroup? {
    guard !fields.isEmpty else {
      return nil
    }
    return ImageMetadataRawGroup(name: name, fields: fields)
  }

  private static func rawFields(
    from dictionary: [CFString: Any],
    skippingDictionaries: Bool = false
  ) -> [ImageMetadataRawField] {
    dictionary
      .compactMap { key, value -> ImageMetadataRawField? in
        if skippingDictionaries, value is NSDictionary {
          return nil
        }

        guard let displayValue = displayString(value) else {
          return nil
        }

        return ImageMetadataRawField(key: displayName(for: key), value: displayValue)
      }
      .sorted { lhs, rhs in
        lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
      }
  }

  private static func displayName(for key: CFString) -> String {
    let rawName = String(key).trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
    return rawName
      .replacingOccurrences(
        of: #"([a-z0-9])([A-Z])"#,
        with: "$1 $2",
        options: .regularExpression
      )
  }

  private static func displayString(_ value: Any) -> String? {
    if let string = value as? String {
      return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    if let number = value as? NSNumber {
      return number.stringValue
    }

    if let date = value as? Date {
      return date.formatted(date: .abbreviated, time: .standard)
    }

    if let values = value as? [Any] {
      return values
        .compactMap(displayString)
        .joined(separator: ", ")
        .nilIfEmpty
    }

    if value is NSDictionary {
      return nil
    }

    return String(describing: value)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
  }

  private static func formatName(from source: CGImageSource) -> String? {
    guard let typeIdentifier = CGImageSourceGetType(source) as String?,
          let type = UTType(typeIdentifier) else {
      return nil
    }

    if let preferredExtension = type.preferredFilenameExtension {
      return preferredExtension.uppercased()
    }

    return type.localizedDescription
  }

  private static func firstDate(from candidates: [String?]) -> Date? {
    for candidate in candidates {
      guard let candidate,
            let date = parseImageDate(candidate) else {
        continue
      }
      return date
    }
    return nil
  }

  private static func parseImageDate(_ value: String) -> Date? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formats = [
      "yyyy:MM:dd HH:mm:ss",
      "yyyy:MM:dd HH:mm:ss.SSS",
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    ]

    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = .current
      formatter.dateFormat = format

      if let date = formatter.date(from: trimmedValue) {
        return date
      }
    }

    return nil
  }

  private static func stringValue(_ value: Any?) -> String? {
    if let string = value as? String {
      let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedString.isEmpty ? nil : trimmedString
    }

    return nil
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return nil
  }

  private static func isoValue(_ value: Any?) -> Int? {
    if let values = value as? [Any] {
      return values.compactMap(intValue).first
    }

    return intValue(value)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
