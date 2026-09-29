import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class GalleryStore {
  var appLanguage: AppLanguage = .stored {
    didSet {
      appLanguage.save()
    }
  }
  var maximizePreviewWindow = false {
    didSet {
      UserDefaults.standard.set(maximizePreviewWindow, forKey: DefaultsKey.maximizePreviewWindow)
    }
  }
  var items: [ImageItem] = [] {
    didSet {
      imagePairs = ImagePairResolver.pairs(in: items)
    }
  }
  private var imagePairs: [ImageItem.ID: ImageItem] = [:]
  var selectedIDs: Set<ImageItem.ID> = []
  var focusedID: ImageItem.ID?
  var currentFolder: URL?
  var recentFolders: [URL] = []
  var favoriteFolders: [URL] = []
  var sidebarSelection: SidebarItem? = .current
  var recursiveScan = true
  var sortOrder: ImageSortOrder = .name
  var sortAscending = true
  var thumbnailSize: Double = 140
  var searchText = ""
  var showFavoritesOnly = false
  var minimumRating = 0
  var showMetadataInspector = false
  var showRAWFiles = false {
    didSet {
      UserDefaults.standard.set(showRAWFiles, forKey: DefaultsKey.showRAWFiles)
      applyFilters()
    }
  }
  var imageRatings: [String: Int] = [:]
  var favoriteImagePaths: Set<String> = []
  var isScanning = false
  var isCopyingFavorites = false
  var isCopyingSelection = false
  var isConfirmingTrashSelection = false
  var errorMessage: String?
  var copyResultMessage: String?

  @ObservationIgnored let thumbnailService = ThumbnailService()
  @ObservationIgnored private let scanner = ImageScanner()
  @ObservationIgnored private let folderMonitor = FolderMonitor()
  @ObservationIgnored private let slideshowPresenter = SlideshowPresenter()
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var selectionAnchorID: ImageItem.ID?
  @ObservationIgnored private var restoredFocusedID: ImageItem.ID?

  init() {
    maximizePreviewWindow = UserDefaults.standard.bool(forKey: DefaultsKey.maximizePreviewWindow)
    recursiveScan = UserDefaults.standard.object(forKey: DefaultsKey.recursiveScan) as? Bool ?? true
    thumbnailSize = UserDefaults.standard.object(forKey: DefaultsKey.thumbnailSize) as? Double ?? 140
    searchText = UserDefaults.standard.string(forKey: DefaultsKey.searchText) ?? ""
    showFavoritesOnly = UserDefaults.standard.bool(forKey: DefaultsKey.showFavoritesOnly)
    showRAWFiles = UserDefaults.standard.bool(forKey: DefaultsKey.showRAWFiles)
    minimumRating = min(max(UserDefaults.standard.integer(forKey: DefaultsKey.minimumRating), 0), 5)

    if let rawSortOrder = UserDefaults.standard.string(forKey: DefaultsKey.sortOrder),
       let storedSortOrder = ImageSortOrder(rawValue: rawSortOrder) {
      sortOrder = storedSortOrder
    }
    sortAscending = UserDefaults.standard.object(forKey: DefaultsKey.sortAscending) as? Bool ?? true

    recentFolders = Self.urls(forKey: DefaultsKey.recentFolders)
    favoriteFolders = Self.urls(forKey: DefaultsKey.favoriteFolders)
    imageRatings = Self.ratings(forKey: DefaultsKey.imageRatings)
    favoriteImagePaths = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.favoriteImagePaths) ?? [])
    showMetadataInspector = UserDefaults.standard.object(forKey: DefaultsKey.showMetadataInspector) as? Bool ?? false

    if let folderPath = UserDefaults.standard.string(forKey: DefaultsKey.lastFolder) {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
        currentFolder = URL(fileURLWithPath: folderPath).standardizedFileURL
        if let focusedPath = UserDefaults.standard.string(forKey: DefaultsKey.focusedImage) {
          restoredFocusedID = URL(fileURLWithPath: focusedPath).standardizedFileURL
        }

        Task { @MainActor [weak self] in
          await Task.yield()
          self?.restoreLastFolder()
        }
      }
    }
  }

  var focusedItem: ImageItem? {
    guard let focusedID else {
      return nil
    }
    return items.first { $0.id == focusedID }
  }

  var selectedItems: [ImageItem] {
    items.filter { selectedIDs.contains($0.id) }
  }

  var filteredItems: [ImageItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return browsableItems.filter { item in
      (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        && (!showFavoritesOnly || isFavorite(item))
        && rating(for: item) >= minimumRating
    }
  }

  var browsableItems: [ImageItem] {
    showRAWFiles ? items : items.filter { !$0.isRAW }
  }

  var isFilterActive: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || showFavoritesOnly
      || minimumRating > 0
  }

  var allSelectedItemsAreFavorite: Bool {
    !selectedIDs.isEmpty && selectedItems.allSatisfy(isFavorite)
  }

  var canCompareSelection: Bool {
    selectedIDs.count == 2 && selectedItems.count == 2
  }

  func chooseFolder() {
    guard let folder = FolderPanel.chooseFolder() else {
      return
    }
    openFolder(folder)
  }

  func openFolder(_ folder: URL) {
    let standardizedFolder = folder.standardizedFileURL
    restoredFocusedID = nil
    currentFolder = standardizedFolder
    sidebarSelection = .current
    pushRecentFolder(standardizedFolder)
    persistBrowsingState()
    scan(folder: standardizedFolder)
  }

  func persistBrowsingState() {
    UserDefaults.standard.set(currentFolder?.path, forKey: DefaultsKey.lastFolder)
    UserDefaults.standard.set(focusedID?.path, forKey: DefaultsKey.focusedImage)
    UserDefaults.standard.set(searchText, forKey: DefaultsKey.searchText)
    UserDefaults.standard.set(showFavoritesOnly, forKey: DefaultsKey.showFavoritesOnly)
    UserDefaults.standard.set(minimumRating, forKey: DefaultsKey.minimumRating)
  }

  func reloadCurrentFolder() {
    guard let currentFolder else {
      return
    }
    scan(folder: currentFolder, preservingSelection: true)
  }

  func persistPreferences() {
    UserDefaults.standard.set(recursiveScan, forKey: DefaultsKey.recursiveScan)
    UserDefaults.standard.set(thumbnailSize, forKey: DefaultsKey.thumbnailSize)
    UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder)
    UserDefaults.standard.set(sortAscending, forKey: DefaultsKey.sortAscending)
    UserDefaults.standard.set(showMetadataInspector, forKey: DefaultsKey.showMetadataInspector)
  }

  func applySortOrder() {
    persistPreferences()
    items = Self.sorted(items, by: sortOrder, ascending: sortAscending)
  }

  func applyFilters() {
    let visibleIDs = Set(filteredItems.map(\.id))
    selectedIDs.formIntersection(visibleIDs)

    if let focusedID, visibleIDs.contains(focusedID) {
      return
    }

    focusedID = filteredItems.first?.id
    selectionAnchorID = focusedID
    if selectedIDs.isEmpty, let focusedID {
      selectedIDs = [focusedID]
    }
  }

  func clearFilters() {
    searchText = ""
    showFavoritesOnly = false
    minimumRating = 0
    applyFilters()
  }

  func addCurrentFolderToFavorites() {
    guard let currentFolder, !favoriteFolders.contains(currentFolder) else {
      return
    }
    favoriteFolders.insert(currentFolder, at: 0)
    saveFolders(favoriteFolders, forKey: DefaultsKey.favoriteFolders)
  }

  func removeRecentFolder(_ folder: URL) {
    recentFolders.removeAll { $0 == folder }
    saveFolders(recentFolders, forKey: DefaultsKey.recentFolders)
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
    selectedIDs = Set(filteredItems.map(\.id))
    focusedID = focusedID ?? filteredItems.first?.id
    selectionAnchorID = focusedID
  }

  func clearSelection() {
    selectedIDs = []
    selectionAnchorID = nil
  }

  func prepareSelection(forContextItem id: ImageItem.ID) {
    if !selectedIDs.contains(id) {
      select(id, extending: false, toggling: false)
    }
  }

  func moveSelection(horizontal: Int, vertical: Int, columns: Int, extending: Bool) {
    let visibleItems = filteredItems
    guard !visibleItems.isEmpty else {
      return
    }

    let safeColumns = max(columns, 1)
    let currentIndex = focusedID.flatMap { id in
      visibleItems.firstIndex { $0.id == id }
    } ?? 0
    let requestedIndex = currentIndex + horizontal + (vertical * safeColumns)
    let newIndex = min(max(requestedIndex, 0), visibleItems.count - 1)
    let newID = visibleItems[newIndex].id

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
    if !selectedIDs.contains(item.id) {
      selectedIDs = [item.id]
      selectionAnchorID = item.id
    }
    slideshowPresenter.show(items: filteredItems, startingAt: item.id, store: self, autoplay: false)
  }

  func startSlideshow() {
    let visibleItems = filteredItems
    guard !visibleItems.isEmpty else {
      return
    }

    let slideshowItems = selectedIDs.isEmpty
      ? visibleItems
      : visibleItems.filter { selectedIDs.contains($0.id) }
    let startID = slideshowItems.contains(where: { $0.id == focusedID }) ? focusedID : slideshowItems.first?.id
    slideshowPresenter.show(items: slideshowItems, startingAt: startID, store: self)
  }

  func compareSelectedImages() {
    guard canCompareSelection else { return }
    slideshowPresenter.showComparison(items: selectedItems, store: self)
  }

  func pairedImage(for item: ImageItem) -> ImageItem? {
    imagePairs[item.id]
  }

  func openPairedPreview(for item: ImageItem) {
    guard let paired = pairedImage(for: item) else { return }
    slideshowPresenter.show(
      items: filteredItems, startingAt: item.id, store: self, autoplay: false,
      displayItem: paired
    )
  }

  func comparePairedImage(for item: ImageItem) {
    guard let paired = pairedImage(for: item) else { return }
    let pair = item.isRAW ? [item, paired] : [paired, item]
    slideshowPresenter.showComparison(items: pair, store: self)
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
    if isFilterActive {
      applyFilters()
    }
  }

  func setRatingForSelection(_ rating: Int) {
    let clampedRating = min(max(rating, 0), 5)

    for item in selectedItems {
      let key = imageStateKey(for: item)
      if clampedRating == 0 {
        imageRatings.removeValue(forKey: key)
      } else {
        imageRatings[key] = clampedRating
      }
    }

    saveImageRatings()
    if isFilterActive {
      applyFilters()
    }
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
    if isFilterActive {
      applyFilters()
    }
  }

  func toggleFavoriteForSelection() {
    let shouldFavorite = !allSelectedItemsAreFavorite

    for item in selectedItems {
      let key = imageStateKey(for: item)
      if shouldFavorite {
        favoriteImagePaths.insert(key)
      } else {
        favoriteImagePaths.remove(key)
      }
    }

    saveFavoriteImagePaths()
    if isFilterActive {
      applyFilters()
    }
  }

  func copyFavoritesToFolder() {
    guard !favoriteImagePaths.isEmpty,
          let destination = FolderPanel.chooseDestinationFolder() else {
      return
    }

    let sourcePaths = favoriteImagePaths.sorted()
    isCopyingFavorites = true

    Task { @MainActor in
      let result = await Task.detached(priority: .userInitiated) {
        Self.copyFiles(at: sourcePaths, to: destination)
      }.value

      isCopyingFavorites = false
      copyResultMessage = L10n.copyFavoritesResult(
        copied: result.copied,
        unavailable: result.unavailable,
        failed: result.failed
      )
    }
  }

  func copySelectedToFolder() {
    let sourcePaths = selectedItems.map { $0.url.standardizedFileURL.path }
    guard !sourcePaths.isEmpty,
          let destination = FolderPanel.chooseDestinationFolder(title: L10n.copySelectedToFolder) else {
      return
    }

    isCopyingSelection = true

    Task { @MainActor in
      let result = await Task.detached(priority: .userInitiated) {
        Self.copyFiles(at: sourcePaths, to: destination)
      }.value

      isCopyingSelection = false
      copyResultMessage = L10n.copyItemsResult(
        copied: result.copied,
        unavailable: result.unavailable,
        failed: result.failed
      )
    }
  }

  func revealSelectionInFinder() {
    let urls = selectedItems.map(\.url)
    guard !urls.isEmpty else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @discardableResult
  func trash(_ item: ImageItem) -> Bool {
    let result = trash([item])
    if let failureDescription = result.failureDescription {
      errorMessage = failureDescription
    }
    return result.moved == 1
  }

  func requestTrashSelection() {
    guard !selectedIDs.isEmpty else {
      return
    }

    if selectedIDs.count == 1 {
      trashSelectedItems()
    } else {
      isConfirmingTrashSelection = true
    }
  }

  func confirmTrashSelection() {
    isConfirmingTrashSelection = false
    trashSelectedItems()
  }

  func trashSelectedItems() {
    let result = trash(selectedItems)
    if result.failed > 0 {
      errorMessage = L10n.trashResult(moved: result.moved, failed: result.failed)
    }
  }

  private func trash(_ targets: [ImageItem]) -> TrashResult {
    guard !targets.isEmpty else {
      return TrashResult()
    }

    let targetIDs = Set(targets.map(\.id))
    let preferredIndex = items.firstIndex { targetIDs.contains($0.id) } ?? 0
    var deletedItems: [ImageItem] = []
    var failedItems: [ImageItem] = []
    var failureDescription: String?

    for item in targets {
      do {
        var resultingItemURL: NSURL?
        try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingItemURL)
        deletedItems.append(item)
      } catch {
        failedItems.append(item)
        failureDescription = failureDescription ?? error.localizedDescription
      }
    }

    removeDeletedItems(deletedItems, preferredIndex: preferredIndex, failedItems: failedItems)
    return TrashResult(
      moved: deletedItems.count,
      failed: failedItems.count,
      failureDescription: failureDescription
    )
  }

  private func removeDeletedItems(
    _ deletedItems: [ImageItem],
    preferredIndex: Int,
    failedItems: [ImageItem]
  ) {
    guard !deletedItems.isEmpty else {
      return
    }

    let deletedIDs = Set(deletedItems.map(\.id))
    let deletedKeys = Set(deletedItems.map(imageStateKey))
    items.removeAll { deletedIDs.contains($0.id) }
    imageRatings = imageRatings.filter { !deletedKeys.contains($0.key) }
    favoriteImagePaths.subtract(deletedKeys)
    saveImageRatings()
    saveFavoriteImagePaths()

    if let firstFailed = failedItems.first {
      selectedIDs = Set(failedItems.map(\.id))
      focusedID = firstFailed.id
      selectionAnchorID = firstFailed.id
      return
    }

    guard !items.isEmpty else {
      selectedIDs = []
      focusedID = nil
      selectionAnchorID = nil
      return
    }

    let visibleItems = filteredItems
    guard !visibleItems.isEmpty else {
      selectedIDs = []
      focusedID = nil
      selectionAnchorID = nil
      return
    }

    let visibleIDs = Set(visibleItems.map(\.id))
    let searchStart = min(preferredIndex, items.count)
    let nextID = items.dropFirst(searchStart).first { visibleIDs.contains($0.id) }?.id
      ?? visibleItems.last!.id
    selectedIDs = [nextID]
    focusedID = nextID
    selectionAnchorID = nextID
  }

  private func scan(folder: URL, preservingSelection: Bool = false) {
    scanTask?.cancel()
    if !preservingSelection {
      folderMonitor.stop()
    }
    let shouldPreserveSelection = preservingSelection && !items.isEmpty
    let previousSelection = selectedIDs
    let previousFocusedID = focusedID

    if !shouldPreserveSelection {
      items = []
      selectedIDs = []
      focusedID = nil
      selectionAnchorID = nil
    }
    isScanning = true
    errorMessage = nil

    let recursiveScan = recursiveScan

    scanTask = Task { @MainActor in
      do {
        let scannedItems = try await scanner.scanFolder(folder, recursive: recursiveScan)
        try Task.checkCancellation()
        items = Self.sorted(scannedItems, by: sortOrder, ascending: sortAscending)
        let visibleIDs = Set(filteredItems.map(\.id))

        if shouldPreserveSelection {
          selectedIDs = previousSelection.intersection(visibleIDs)
          focusedID = previousFocusedID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? selectedIDs.first
            ?? filteredItems.first?.id
        } else {
          focusedID = restoredFocusedID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? filteredItems.first?.id
          selectedIDs = focusedID.map { [$0] } ?? []
          restoredFocusedID = nil
        }

        selectionAnchorID = focusedID
        persistBrowsingState()
        isScanning = false
        startMonitoring(folder: folder, recursive: recursiveScan)
      } catch is CancellationError {
      } catch {
        isScanning = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func restoreLastFolder() {
    guard let currentFolder else {
      return
    }
    sidebarSelection = .current
    scan(folder: currentFolder)
  }

  private func startMonitoring(folder: URL, recursive: Bool) {
    folderMonitor.start(folder: folder, recursive: recursive) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.currentFolder == folder else {
          return
        }
        self.scan(folder: folder, preservingSelection: true)
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

  private func imageStateKey(for item: ImageItem) -> String {
    item.url.standardizedFileURL.path
  }

  nonisolated private static func copyFiles(at sourcePaths: [String], to destination: URL) -> CopyResult {
    let fileManager = FileManager.default
    var result = CopyResult()

    for sourcePath in sourcePaths {
      let source = URL(fileURLWithPath: sourcePath)
      guard fileManager.fileExists(atPath: source.path) else {
        result.unavailable += 1
        continue
      }

      let target = availableDestination(for: source, in: destination, fileManager: fileManager)
      do {
        try fileManager.copyItem(at: source, to: target)
        result.copied += 1
      } catch {
        result.failed += 1
      }
    }

    return result
  }

  nonisolated private static func availableDestination(
    for source: URL,
    in folder: URL,
    fileManager: FileManager
  ) -> URL {
    let initialTarget = folder.appendingPathComponent(source.lastPathComponent)
    guard fileManager.fileExists(atPath: initialTarget.path) else {
      return initialTarget
    }

    let fileExtension = source.pathExtension
    let basename = source.deletingPathExtension().lastPathComponent
    var index = 2

    while true {
      let filename = fileExtension.isEmpty ? "\(basename) \(index)" : "\(basename) \(index).\(fileExtension)"
      let candidate = folder.appendingPathComponent(filename)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  private func indexOfItem(id: ImageItem.ID) -> Int? {
    items.firstIndex { $0.id == id }
  }

  private func idsBetween(_ first: ImageItem.ID, _ second: ImageItem.ID) -> Set<ImageItem.ID> {
    let visibleItems = filteredItems
    guard let firstIndex = visibleItems.firstIndex(where: { $0.id == first }),
          let secondIndex = visibleItems.firstIndex(where: { $0.id == second }) else {
      return [second]
    }

    let range = min(firstIndex, secondIndex)...max(firstIndex, secondIndex)
    return Set(visibleItems[range].map(\.id))
  }

  private static func sorted(_ items: [ImageItem], by sortOrder: ImageSortOrder, ascending: Bool) -> [ImageItem] {
    switch sortOrder {
    case .name:
      items.sorted {
        $0.name.localizedStandardCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
      }
    case .dateTaken:
      items.sorted { lhs, rhs in
        switch (lhs.dateTaken, rhs.dateTaken) {
        case let (lhsDate?, rhsDate?):
          if lhsDate != rhsDate {
            return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
          }
          return lhs.name.localizedStandardCompare(rhs.name) == (ascending ? .orderedAscending : .orderedDescending)
        case (_?, nil):
          return true
        case (nil, _?):
          return false
        case (nil, nil):
          if let lhsModified = lhs.modifiedAt,
             let rhsModified = rhs.modifiedAt,
             lhsModified != rhsModified {
            return ascending ? lhsModified < rhsModified : lhsModified > rhsModified
          }
          return lhs.name.localizedStandardCompare(rhs.name) == (ascending ? .orderedAscending : .orderedDescending)
        }
      }
    case .dateModified:
      items.sorted {
        let lhs = ($0.modifiedAt ?? .distantPast, $0.name)
        let rhs = ($1.modifiedAt ?? .distantPast, $1.name)
        return ascending ? lhs < rhs : lhs > rhs
      }
    case .fileSize:
      items.sorted {
        let lhs = ($0.fileSize, $0.name)
        let rhs = ($1.fileSize, $1.name)
        return ascending ? lhs < rhs : lhs > rhs
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

private struct CopyResult: Sendable {
  var copied = 0
  var unavailable = 0
  var failed = 0
}

private struct TrashResult {
  var moved = 0
  var failed = 0
  var failureDescription: String?
}

private enum DefaultsKey {
  static let showRAWFiles = "showRAWFiles"
  static let maximizePreviewWindow = "maximizePreviewWindow"
  static let recursiveScan = "recursiveScan"
  static let thumbnailSize = "thumbnailSize"
  static let sortOrder = "sortOrder"
  static let sortAscending = "sortAscending"
  static let showMetadataInspector = "showMetadataInspector"
  static let recentFolders = "recentFolders"
  static let favoriteFolders = "favoriteFolders"
  static let imageRatings = "imageRatings"
  static let favoriteImagePaths = "favoriteImagePaths"
  static let lastFolder = "lastFolder"
  static let focusedImage = "focusedImage"
  static let searchText = "searchText"
  static let showFavoritesOnly = "showFavoritesOnly"
  static let minimumRating = "minimumRating"
}
