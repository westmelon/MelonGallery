import Foundation

enum ImageSortOrder: String, CaseIterable, Identifiable, Sendable {
  case name
  case dateTaken
  case dateModified
  case fileSize

  var id: String { rawValue }

  var title: String {
    switch self {
    case .name:
      L10n.name
    case .dateTaken:
      L10n.dateTaken
    case .dateModified:
      L10n.dateModified
    case .fileSize:
      L10n.fileSize
    }
  }
}
