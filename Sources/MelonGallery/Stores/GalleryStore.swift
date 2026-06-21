import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class GalleryStore {
  var items: [ImageItem] = []
  var selectedIDs: Set<ImageItem.ID> = []
  var focusedID: ImageItem.ID?
  var currentFolder: URL?
  var recentFolders: [URL] = []
  var favoriteFolders: [URL] = []
  var sidebarSelection: SidebarItem? = .current
  var recursiveScan = true
  var sortOrder: ImageSortOrder = .name
  var thumbnailSize: Double = 140
  var showMetadataInspector = false
  var imageRatings: [String: Int] = [:]
  var favoriteImagePaths: Set<String> = []
  var isScanning = false
  var errorMessage: String?

  @ObservationIgnored let thumbnailService = ThumbnailService()
  @ObservationIgnored private let scanner = ImageScanner()
  @ObservationIgnored private let slideshowPresenter = SlideshowPresenter()
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var selectionAnchorID: ImageItem.ID?

  init() {
    recursiveScan = UserDefaults.standard.object(forKey: DefaultsKey.recursiveScan) as? Bool ?? true
    thumbnailSize = UserDefaults.standard.object(forKey: DefaultsKey.thumbnailSize) as? Double ?? 140

    if let rawSortOrder = UserDefaults.standard.string(forKey: DefaultsKey.sortOrder),
       let storedSortOrder = ImageSortOrder(rawValue: rawSortOrder) {
      sortOrder = storedSortOrder
    }

    recentFolders = Self.urls(forKey: DefaultsKey.recentFolders)
    favoriteFolders = Self.urls(forKey: DefaultsKey.favoriteFolders)
    imageRatings = Self.ratings(forKey: DefaultsKey.imageRatings)
    favoriteImagePaths = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.favoriteImagePaths) ?? [])
    showMetadataInspector = UserDefaults.standard.object(forKey: DefaultsKey.showMetadataInspector) as? Bool ?? false
  }

  var focusedItem: ImageItem? {
    guard let focusedID else {
      return nil
    }
    return items.first { $0.id == focusedID }
  }

  func chooseFolder() {
    guard let folder = FolderPanel.chooseFolder() else {
      return
    }
    openFolder(folder)
  }

  func openFolder(_ folder: URL) {
    let standardizedFolder = folder.standardizedFileURL
    currentFolder = standardizedFolder
    sidebarSelection = .current
    pushRecentFolder(standardizedFolder)
    scan(folder: standardizedFolder)
  }

  func reloadCurrentFolder() {
    guard let currentFolder else {
      return
    }
    scan(folder: currentFolder)
  }

  func persistPreferences() {
    UserDefaults.standard.set(recursiveScan, forKey: DefaultsKey.recursiveScan)
    UserDefaults.standard.set(thumbnailSize, forKey: DefaultsKey.thumbnailSize)
    UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder)
    UserDefaults.standard.set(showMetadataInspector, forKey: DefaultsKey.showMetadataInspector)
  }

  func applySortOrder() {
    persistPreferences()
    items = Self.sorted(items, by: sortOrder)
  }

  func addCurrentFolderToFavorites() {
    guard let currentFolder, !favoriteFolders.contains(currentFolder) else {
      return
    }
    favoriteFolders.insert(currentFolder, at: 0)
    saveFolders(favoriteFolders, forKey: DefaultsKey.favoriteFolders)
  }

  func removeFavorite(_ folder: URL) {
    favoriteFolders.removeAll { $0 == folder }
    saveFolders(favoriteFolders, forKey: DefaultsKey.favoriteFolders)
  }

  func handleSidebarSelection(_ selection: SidebarItem?) {
    switch selection {
    case .recent(let folder), .favorite(let folder):
      openFolder(folder)
    case .current, .none:
      break
    }
  }

  func select(_ id: ImageItem.ID, extending: Bool, toggling: Bool) {
    if extending, let anchor = selectionAnchorID {
      selectedIDs = idsBetween(anchor, id)
      focusedID = id
      return
    }

    if toggling {
      if selectedIDs.contains(id) {
        selectedIDs.remove(id)
      } else {
        selectedIDs.insert(id)
      }
      focusedID = id
      selectionAnchorID = id
      return
    }

    selectedIDs = [id]
    focusedID = id
    selectionAnchorID = id
  }

  func selectAll() {
    selectedIDs = Set(items.map(\.id))
    focusedID = focusedID ?? items.first?.id
    selectionAnchorID = focusedID
  }

  func moveSelection(horizontal: Int, vertical: Int, columns: Int, extending: Bool) {
    guard !items.isEmpty else {
      return
    }

    let safeColumns = max(columns, 1)
    let currentIndex = focusedID.flatMap(indexOfItem) ?? 0
    let requestedIndex = currentIndex + horizontal + (vertical * safeColumns)
    let newIndex = min(max(requestedIndex, 0), items.count - 1)
    let newID = items[newIndex].id

    if extending, let anchor = selectionAnchorID {
      selectedIDs = idsBetween(anchor, newID)
    } else {
      selectedIDs = [newID]
      selectionAnchorID = newID
    }

    focusedID = newID
  }

  func openFocusedPreview() {
    guard let focusedID,
          let item = items.first(where: { $0.id == focusedID }) else {
      return
    }
    openPreview(item)
  }

  func openPreview(_ item: ImageItem) {
    focusedID = item.id
    selectedIDs = [item.id]
    selectionAnchorID = item.id
    slideshowPresenter.show(items: items, startingAt: item.id, store: self, autoplay: false)
  }

  func startSlideshow() {
    guard !items.isEmpty else {
      return
    }

    let slideshowItems = selectedIDs.isEmpty ? items : items.filter { selectedIDs.contains($0.id) }
    let startID = slideshowItems.contains(where: { $0.id == focusedID }) ? focusedID : slideshowItems.first?.id
    slideshowPresenter.show(items: slideshowItems, startingAt: startID, store: self)
  }

  func rating(for item: ImageItem) -> Int {
    imageRatings[imageStateKey(for: item)] ?? 0
  }

  func setRating(_ rating: Int, for item: ImageItem) {
    let clampedRating = min(max(rating, 0), 5)
    let key = imageStateKey(for: item)

    if clampedRating == 0 {
      imageRatings.removeValue(forKey: key)
    } else {
      imageRatings[key] = clampedRating
    }

    saveImageRatings()
  }

  func isFavorite(_ item: ImageItem) -> Bool {
    favoriteImagePaths.contains(imageStateKey(for: item))
  }

  func toggleFavorite(_ item: ImageItem) {
    let key = imageStateKey(for: item)

    if favoriteImagePaths.contains(key) {
      favoriteImagePaths.remove(key)
    } else {
      favoriteImagePaths.insert(key)
    }

    saveFavoriteImagePaths()
  }

  @discardableResult
  func trash(_ item: ImageItem) -> Bool {
    do {
      var resultingItemURL: NSURL?
      try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingItemURL)
      removeDeletedItem(item)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func scan(folder: URL) {
    scanTask?.cancel()
    items = []
    selectedIDs = []
    focusedID = nil
    selectionAnchorID = nil
    isScanning = true
    errorMessage = nil

    let recursiveScan = recursiveScan
    let sortOrder = sortOrder

    scanTask = Task { @MainActor in
      do {
        let scannedItems = try await scanner.scanFolder(folder, recursive: recursiveScan)
        try Task.checkCancellation()
        items = Self.sorted(scannedItems, by: sortOrder)
        focusedID = items.first?.id
        selectedIDs = focusedID.map { [$0] } ?? []
        selectionAnchorID = focusedID
        isScanning = false
      } catch is CancellationError {
      } catch {
        isScanning = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func pushRecentFolder(_ folder: URL) {
    recentFolders.removeAll { $0 == folder }
    recentFolders.insert(folder, at: 0)
    recentFolders = Array(recentFolders.prefix(8))
    saveFolders(recentFolders, forKey: DefaultsKey.recentFolders)
  }

  private func saveFolders(_ folders: [URL], forKey key: String) {
    UserDefaults.standard.set(folders.map(\.path), forKey: key)
  }

  private func saveImageRatings() {
    UserDefaults.standard.set(imageRatings, forKey: DefaultsKey.imageRatings)
  }

  private func saveFavoriteImagePaths() {
    UserDefaults.standard.set(Array(favoriteImagePaths), forKey: DefaultsKey.favoriteImagePaths)
  }

  private func removeDeletedItem(_ item: ImageItem) {
    let deletedID = item.id
    let deletedKey = imageStateKey(for: item)
    let deletedIndex = items.firstIndex { $0.id == deletedID } ?? focusedID.flatMap(indexOfItem) ?? 0

    items.removeAll { $0.id == deletedID }
    imageRatings.removeValue(forKey: deletedKey)
    favoriteImagePaths.remove(deletedKey)
    saveImageRatings()
    saveFavoriteImagePaths()

    guard !items.isEmpty else {
      selectedIDs = []
      focusedID = nil
      selectionAnchorID = nil
      return
    }

    let nextIndex = min(deletedIndex, items.count - 1)
    let nextID = items[nextIndex].id
    focusedID = nextID
    selectedIDs = [nextID]
    selectionAnchorID = nextID
  }

  private func imageStateKey(for item: ImageItem) -> String {
    item.url.standardizedFileURL.path
  }

  private func indexOfItem(id: ImageItem.ID) -> Int? {
    items.firstIndex { $0.id == id }
  }

  private func idsBetween(_ first: ImageItem.ID, _ second: ImageItem.ID) -> Set<ImageItem.ID> {
    guard let firstIndex = indexOfItem(id: first),
          let secondIndex = indexOfItem(id: second) else {
      return [second]
    }

    let range = min(firstIndex, secondIndex)...max(firstIndex, secondIndex)
    return Set(items[range].map(\.id))
  }

  private static func sorted(_ items: [ImageItem], by sortOrder: ImageSortOrder) -> [ImageItem] {
    switch sortOrder {
    case .name:
      items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    case .dateTaken:
      items.sorted { lhs, rhs in
        switch (lhs.dateTaken, rhs.dateTaken) {
        case let (lhsDate?, rhsDate?):
          if lhsDate != rhsDate {
            return lhsDate < rhsDate
          }
          return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case (_?, nil):
          return true
        case (nil, _?):
          return false
        case (nil, nil):
          if let lhsModified = lhs.modifiedAt,
             let rhsModified = rhs.modifiedAt,
             lhsModified != rhsModified {
            return lhsModified < rhsModified
          }
          return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
      }
    case .dateModified:
      items.sorted {
        ($0.modifiedAt ?? .distantPast, $0.name) < ($1.modifiedAt ?? .distantPast, $1.name)
      }
    case .fileSize:
      items.sorted {
        ($0.fileSize, $0.name) < ($1.fileSize, $1.name)
      }
    }
  }

  private static func urls(forKey key: String) -> [URL] {
    let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
    return paths.map { URL(fileURLWithPath: $0) }
  }

  private static func ratings(forKey key: String) -> [String: Int] {
    let dictionary = UserDefaults.standard.dictionary(forKey: key) ?? [:]
    return dictionary.reduce(into: [:]) { ratings, pair in
      guard let rating = pair.value as? Int,
            (1...5).contains(rating) else {
        return
      }
      ratings[pair.key] = rating
    }
  }
}

private enum DefaultsKey {
  static let recursiveScan = "recursiveScan"
  static let thumbnailSize = "thumbnailSize"
  static let sortOrder = "sortOrder"
  static let showMetadataInspector = "showMetadataInspector"
  static let recentFolders = "recentFolders"
  static let favoriteFolders = "favoriteFolders"
  static let imageRatings = "imageRatings"
  static let favoriteImagePaths = "favoriteImagePaths"
}
