import Foundation

enum L10n {
  static var appName: String { string("Melon Gallery") }
  static var addFavorite: String { string("Add Favorite") }
  static var currentFolder: String { string("Current Folder") }
  static var aperture: String { string("Aperture") }
  static var camera: String { string("Camera") }
  static var clearRating: String { string("Clear Rating") }
  static var dateModified: String { string("Date Modified") }
  static var dateTaken: String { string("Date Taken") }
  static var details: String { string("Details") }
  static var dimensions: String { string("Dimensions") }
  static var error: String { string("Error") }
  static var exposureTime: String { string("Exposure Time") }
  static var favorite: String { string("Favorite") }
  static var favoriteFolders: String { string("Favorite Folders") }
  static var fileSize: String { string("File Size") }
  static var focalLength: String { string("Focal Length") }
  static var format: String { string("Format") }
  static var folders: String { string("Folders") }
  static var galleryMenu: String { string("Gallery") }
  static var gps: String { string("GPS") }
  static var info: String { string("Info") }
  static var iso: String { string("ISO") }
  static var lens: String { string("Lens") }
  static var metadata: String { string("Metadata") }
  static var name: String { string("Name") }
  static var noFavorites: String { string("No Favorites") }
  static var noFolderSelected: String { string("No folder selected") }
  static var noImages: String { string("No Images") }
  static var noRecentFolders: String { string("No Recent Folders") }
  static var noSelection: String { string("No Selection") }
  static var path: String { string("Path") }
  static var ok: String { string("OK") }
  static var open: String { string("Open") }
  static var openFolder: String { string("Open Folder") }
  static var openPreview: String { string("Open Preview") }
  static var paused: String { string("Paused") }
  static var moveToTrash: String { string("Move to Trash") }
  static var recentOpened: String { string("Recent Opened") }
  static var rating: String { string("Rating") }
  static var recursiveScan: String { string("Recursive Scan") }
  static var removeFavorite: String { string("Remove Favorite") }
  static var scanning: String { string("Scanning...") }
  static var selectAll: String { string("Select All") }
  static var sort: String { string("Sort") }
  static var slideshow: String { string("Slideshow") }
  static var startSlideshow: String { string("Start Slideshow") }
  static var thumbnailSize: String { string("Thumbnail Size") }
  static var unfavorite: String { string("Unfavorite") }
  static var yes: String { string("Yes") }
  static var no: String { string("No") }

  static func imageCount(_ count: Int) -> String {
    String(format: string("%d images"), locale: Locale.current, count)
  }

  static func selectedCount(_ count: Int) -> String {
    String(format: string("%d selected"), locale: Locale.current, count)
  }

  static func string(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .module)
  }
}
