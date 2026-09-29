import Foundation

enum L10n {
  static var appName: String { string("Melon Gallery") }
  static var addFavorite: String { string("Add Favorite") }
  static var actualSize: String { string("Actual Size") }
  static var anyRating: String { string("Any Rating") }
  static var currentFolder: String { string("Current Folder") }
  static var aperture: String { string("Aperture") }
  static var camera: String { string("Camera") }
  static var cancel: String { string("Cancel") }
  static var clearRating: String { string("Clear Rating") }
  static var clearFilters: String { string("Clear Filters") }
  static var choose: String { string("Choose") }
  static var copyComplete: String { string("Copy Complete") }
  static var compareImages: String { string("Compare Images") }
  static var copyFavoritesToFolder: String { string("Copy Favorites to Folder...") }
  static var copySelectedToFolder: String { string("Copy Selected to Folder...") }
  static var dateModified: String { string("Date Modified") }
  static var dateTaken: String { string("Date Taken") }
  static var details: String { string("Details") }
  static var dimensions: String { string("Dimensions") }
  static var error: String { string("Error") }
  static var exposureTime: String { string("Exposure Time") }
  static var favorite: String { string("Favorite") }
  static var favoriteFolders: String { string("Favorite Folders") }
  static var maximizePreviewWindow: String { string("Maximize Preview Window on Open") }
  static var fitToWindow: String { string("Fit to Window") }
  static var filter: String { string("Filter") }
  static var fileSize: String { string("File Size") }
  static var focalLength: String { string("Focal Length") }
  static var format: String { string("Format") }
  static var folders: String { string("Folders") }
  static var galleryMenu: String { string("Gallery") }
  static var gps: String { string("GPS") }
  static var info: String { string("Info") }
  static var iso: String { string("ISO") }
  static var lens: String { string("Lens") }
  static var language: String { string("Language") }
  static var metadata: String { string("Metadata") }
  static var minimumRating: String { string("Minimum Rating") }
  static var name: String { string("Name") }
  static var noFavorites: String { string("No Favorites") }
  static var noFolderSelected: String { string("No folder selected") }
  static var noImages: String { string("No Images") }
  static var noMatchingImages: String { string("No Matching Images") }
  static var noRecentFolders: String { string("No Recent Folders") }
  static var noSelection: String { string("No Selection") }
  static var path: String { string("Path") }
  static var ok: String { string("OK") }
  static var open: String { string("Open") }
  static var openFolder: String { string("Open Folder") }
  static var openPreview: String { string("Open Preview") }
  static var paused: String { string("Paused") }
  static var moveToTrash: String { string("Move to Trash") }
  static var moveSelectedToTrash: String { string("Move Selected Items to Trash?") }
  static var recentOpened: String { string("Recent Opened") }
  static var rating: String { string("Rating") }
  static var ruleOfThirds: String { string("Rule of Thirds Grid") }
  static var recursiveScan: String { string("Recursive Scan") }
  static var retryThumbnail: String { string("Retry Thumbnail") }
  static var retry: String { string("Retry") }
  static var removeFavorite: String { string("Remove Favorite") }
  static var removeFromRecent: String { string("Remove from Recent") }
  static var scanning: String { string("Scanning...") }
  static var searchImages: String { string("Search Images") }
  static var selectAll: String { string("Select All") }
  static var showFavoritesOnly: String { string("Show Favorites Only") }
  static var showRAWFiles: String { string("Show RAW Files") }
  static var switchToRAW: String { string("Switch to Paired RAW") }
  static var switchToJPEG: String { string("Switch to Paired JPEG") }
  static var compareRAWAndJPEG: String { string("Compare RAW and JPEG") }
  static var rawFilesHidden: String { string("RAW Files Are Hidden") }
  static var fullResolutionRAW: String { string("Full-Resolution RAW") }
  static var parseRAW: String { string("Parse RAW") }
  static var unableToLoadFullRAW: String { string("Unable to Load Full-Resolution RAW") }
  static var embeddedRAWPreview: String { string("Embedded RAW Preview") }
  static var systemRAWPreview: String { string("System RAW Preview") }
  static var showInFinder: String { string("Show in Finder") }
  static var sort: String { string("Sort") }
  static var sortAscending: String { string("Ascending") }
  static var sortDescending: String { string("Descending") }
  static var slideshow: String { string("Slideshow") }
  static var startSlideshow: String { string("Start Slideshow") }
  static var swapSides: String { string("Swap Sides") }
  static var synchronizeViews: String { string("Synchronize Zoom and Pan") }
  static var systemDefault: String { string("System Default") }
  static var thumbnailSize: String { string("Thumbnail Size") }
  static var unfavorite: String { string("Unfavorite") }
  static var unableToLoadImage: String { string("Unable to Load Image") }
  static var yes: String { string("Yes") }
  static var no: String { string("No") }
  static var zoomIn: String { string("Zoom In") }
  static var zoomOut: String { string("Zoom Out") }

  static func imageCount(_ count: Int) -> String {
    String(format: string("%d images"), locale: AppLanguage.stored.locale, count)
  }

  static func selectedCount(_ count: Int) -> String {
    String(format: string("%d selected"), locale: AppLanguage.stored.locale, count)
  }

  static func filteredImageCount(_ filtered: Int, total: Int) -> String {
    String(
      format: string("%d of %d images"),
      locale: AppLanguage.stored.locale,
      filtered,
      total
    )
  }

  static func copyFavoritesResult(copied: Int, unavailable: Int, failed: Int) -> String {
    String(
      format: string("Copied %d favorites; %d unavailable; %d failed."),
      locale: AppLanguage.stored.locale,
      copied,
      unavailable,
      failed
    )
  }

  static func copyItemsResult(copied: Int, unavailable: Int, failed: Int) -> String {
    String(
      format: string("Copied %d items; %d unavailable; %d failed."),
      locale: AppLanguage.stored.locale,
      copied,
      unavailable,
      failed
    )
  }

  static func trashConfirmation(_ count: Int) -> String {
    String(
      format: string("This will move %d selected items to the Trash."),
      locale: AppLanguage.stored.locale,
      count
    )
  }

  static func trashResult(moved: Int, failed: Int) -> String {
    String(
      format: string("Moved %d items to the Trash; %d failed."),
      locale: AppLanguage.stored.locale,
      moved,
      failed
    )
  }

  static func string(_ key: String) -> String {
    let language = AppLanguage.stored
    return language.localizationBundle.localizedString(forKey: key, value: key, table: nil)
  }
}
